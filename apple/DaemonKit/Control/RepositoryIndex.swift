import CryptoKit
import Foundation

/// Registro local de un repositorio: lo que Daemon sabe sin volver a leerlo.
public struct RepositoryRecord: Codable, Sendable {
    public let path: String
    public let name: String
    public let fingerprint: String
    public let insights: RepositoryInsights
    public let git: GitInsights
    public let scannedAt: Date
    public let scanMs: Int
    public var github: GitHubSnapshot?
    public var reused: Bool = false

    public var age: TimeInterval { Date().timeIntervalSince(scannedAt) }
}

/// Resumen compacto para el agente: es lo único que viaja a un LLM.
public struct ContextDigest: Codable, Sendable {
    public struct Repo: Codable, Sendable {
        public let name: String
        public let branch: String?
        public let head: String?
        public let dirty: Bool?
        public let ahead: Int?
        public let behind: Int?
        public let files: Int
        public let lines: Int
        public let languages: [String]
        public let capabilities: [String]
        public let changedFiles: Int
        public let lastCommit: String?
        public let openPRs: Int?
        public let github: String?
    }
    public let generatedAt: Date
    public let repositories: [Repo]
}

public enum RepositoryFingerprint {
    /// HEAD + estado de trabajo: si no cambia, el índice se reutiliza.
    public static func make(head: String?, statusPorcelain: String) -> String {
        let digest = SHA256.hash(data: Data(((head ?? "nohead") + "\n" + statusPorcelain).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#if os(macOS)
public actor RepositoryIndex {
    public static let shared = RepositoryIndex()
    private var memory: [String: RepositoryRecord] = [:]
    /// Tiempo máximo de reutilización aunque la huella no cambie (actividad reciente).
    private let maximumAge: TimeInterval = 3600

    static func fileName(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return "index/\(digest).json"
    }

    public func cached(_ path: String) -> RepositoryRecord? {
        memory[path] ?? DaemonStore.read(RepositoryRecord.self, from: Self.fileName(path))
    }

    /// Devuelve el registro, reescaneando solo si la huella Git cambió.
    public func record(for repository: RepositorySnapshot, force: Bool = false) async -> RepositoryRecord {
        let path = repository.path
        let status = try? await CommandRunner.run("/usr/bin/git", GitInsightsProbe.prefix + ["-C", path, "status", "--porcelain=v2", "--untracked-files=normal"], timeout: 6)
        let fingerprint = RepositoryFingerprint.make(head: repository.head, statusPorcelain: status?.standardOutput ?? UUID().uuidString)
        if !force, var existing = cached(path), existing.fingerprint == fingerprint, existing.age < maximumAge {
            existing.reused = true
            memory[path] = existing
            return existing
        }
        let started = Date()
        async let insights = Task.detached(priority: .utility) { RepositoryInspector.inspect(path: path) }.value
        async let git = GitInsightsProbe.observe(path: path)
        var record = RepositoryRecord(path: path, name: repository.name, fingerprint: fingerprint, insights: await insights, git: await git,
                                      scannedAt: started, scanMs: Int(Date().timeIntervalSince(started) * 1000),
                                      github: cached(path)?.github)
        record.reused = false
        memory[path] = record
        DaemonStore.write(record, to: Self.fileName(path))
        return record
    }

    public func attachGitHub(_ snapshot: GitHubSnapshot, to path: String) {
        guard var record = cached(path) else { return }
        record.github = snapshot
        memory[path] = record
        DaemonStore.write(record, to: Self.fileName(path))
    }

    public func digest(for repositories: [RepositorySnapshot]) -> ContextDigest {
        let repos = repositories.map { repository -> ContextDigest.Repo in
            let record = cached(repository.path)
            return .init(name: repository.name, branch: repository.branch, head: repository.head.map { String($0.prefix(7)) },
                         dirty: repository.dirty, ahead: repository.ahead, behind: repository.behind,
                         files: record?.insights.fileCount ?? 0, lines: record?.insights.sourceLines ?? 0,
                         languages: record?.insights.languages.prefix(4).map(\.name) ?? [],
                         capabilities: record?.insights.capabilities ?? [],
                         changedFiles: record?.git.workingChanges.count ?? 0,
                         lastCommit: record?.git.recent.first.map { "\($0.shortHash) \($0.subject)" },
                         openPRs: record?.github?.openPullRequests.count, github: record?.git.remoteSlug)
        }
        let digest = ContextDigest(generatedAt: Date(), repositories: repos)
        DaemonStore.write(digest, to: "context.json")
        return digest
    }
}
#endif
