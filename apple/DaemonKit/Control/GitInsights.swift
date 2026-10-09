import Foundation

public struct CommitEvent: Codable, Sendable, Hashable, Identifiable {
    public let hash: String
    public let timestamp: Date
    public let subject: String
    public let author: String
    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
}

public struct FileChange: Codable, Sendable, Hashable, Identifiable {
    public let path: String
    public let added: Int?
    public let removed: Int?
    public var id: String { path }
}

public struct GitInsights: Codable, Sendable {
    public let commitCount: Int?
    public let commitsLast7Days: Int?
    public let branchCount: Int?
    public let recent: [CommitEvent]
    public let workingChanges: [FileChange]
    public let untrackedCount: Int?
    public let remoteSlug: String?
    public let provenance: Provenance

    public static let empty = GitInsights(commitCount: nil, commitsLast7Days: nil, branchCount: nil, recent: [], workingChanges: [],
                                          untrackedCount: nil, remoteSlug: nil, provenance: Provenance(source: "git", method: "no ejecutado"))

    public var linesAdded: Int { workingChanges.compactMap(\.added).reduce(0, +) }
    public var linesRemoved: Int { workingChanges.compactMap(\.removed).reduce(0, +) }
}

public enum GitParser {
    /// `git log --format=%H%x1f%ct%x1f%an%x1f%s`
    public static func log(_ text: String) -> [CommitEvent] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0].count >= 7, let seconds = TimeInterval(parts[1]) else { return nil }
            return CommitEvent(hash: String(parts[0]), timestamp: Date(timeIntervalSince1970: seconds),
                               subject: String(parts[3]), author: String(parts[2]))
        }
    }

    /// `git diff --numstat` (binarios aparecen como "-").
    public static func numstat(_ text: String) -> [FileChange] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return FileChange(path: String(parts[2]), added: Int(parts[0]), removed: Int(parts[1]))
        }
    }

    /// owner/repo desde una URL de remoto, sin credenciales.
    public static func githubSlug(_ remote: String) -> String? {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(of: #"github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?/?$"#, options: .regularExpression) else { return nil }
        let tail = value[range].replacingOccurrences(of: "github.com", with: "").drop { $0 == ":" || $0 == "/" }
        var slug = String(tail)
        if slug.hasSuffix("/") { slug.removeLast() }
        if slug.hasSuffix(".git") { slug.removeLast(4) }
        return slug
    }
}

#if os(macOS)
public enum GitInsightsProbe {
    static let prefix = ["--no-pager", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]

    static func git(_ path: String, _ arguments: [String], timeout: TimeInterval = 6) async -> CommandResult? {
        try? await CommandRunner.run("/usr/bin/git", prefix + ["-C", path] + arguments, timeout: timeout)
    }

    public static func observe(path: String) async -> GitInsights {
        async let count = git(path, ["rev-list", "--count", "HEAD"])
        async let week = git(path, ["rev-list", "--count", "--since=7.days", "HEAD"])
        async let branches = git(path, ["branch", "-a", "--format=%(refname:short)"])
        async let log = git(path, ["log", "--no-color", "--format=%H%x1f%ct%x1f%an%x1f%s", "-15"])
        async let diff = git(path, ["diff", "--no-ext-diff", "--no-textconv", "--numstat", "HEAD"])
        async let untracked = git(path, ["ls-files", "--others", "--exclude-standard"])
        async let remote = git(path, ["remote", "get-url", "origin"])
        func integer(_ result: CommandResult?) -> Int? {
            guard let result, result.succeeded else { return nil }
            return Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let branchList = await branches
        let untrackedList = await untracked
        let remoteValue = await remote
        return GitInsights(
            commitCount: integer(await count),
            commitsLast7Days: integer(await week),
            branchCount: branchList.flatMap { $0.succeeded ? $0.standardOutput.split(whereSeparator: \.isNewline).filter { !$0.hasSuffix("/HEAD") && !$0.isEmpty }.count : nil },
            recent: GitParser.log(await log?.standardOutput ?? ""),
            workingChanges: GitParser.numstat(await diff?.standardOutput ?? ""),
            untrackedCount: untrackedList.flatMap { $0.succeeded ? $0.standardOutput.split(whereSeparator: \.isNewline).count : nil },
            remoteSlug: remoteValue.flatMap { $0.succeeded ? GitParser.githubSlug($0.standardOutput) : nil },
            provenance: Provenance(source: "/usr/bin/git", method: "rev-list · log · diff --numstat · ls-files (lectura)")
        )
    }

    /// Diff resumido (stat) para mostrar en el chat. Redactado por el núcleo.
    public static func diffStat(path: String) async -> String {
        guard let result = await git(path, ["diff", "--no-ext-diff", "--no-textconv", "--stat", "HEAD"]) else { return "diff no disponible" }
        let text = result.displayOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Sin cambios respecto a HEAD." : text
    }
}
#endif
