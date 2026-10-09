import Foundation

public struct LanguageMetric: Identifiable, Sendable {
    public let name: String
    public let files: Int
    public var id: String { name }
}

public struct RepositoryInsights: Sendable {
    public let fileCount: Int
    public let sourceLines: Int
    public let bytes: Int64
    public let languages: [LanguageMetric]
    public let capabilities: [String]
    public let blenderAvailable: Bool
    public let abletonAvailable: Bool
    public let hasLogin: Bool
    public let hasDatabase: Bool
    public let usernames: [String]

    public static let empty = RepositoryInsights(
        fileCount: 0, sourceLines: 0, bytes: 0, languages: [], capabilities: [],
        blenderAvailable: false, abletonAvailable: false, hasLogin: false,
        hasDatabase: false, usernames: []
    )
}

public enum RepositoryInspector {
    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", "build", "dist", "node_modules", ".next", "Pods", "DerivedData", ".expo"
    ]

    private static let languageByExtension: [String: String] = [
        "swift": "Swift", "cpp": "C++", "cc": "C++", "cxx": "C++", "c": "C/C++",
        "h": "Headers", "hpp": "Headers", "ts": "TypeScript", "tsx": "TypeScript",
        "js": "JavaScript", "jsx": "JavaScript", "py": "Python", "rs": "Rust",
        "html": "Web", "css": "Web", "scss": "Web", "sql": "SQL", "md": "Docs"
    ]

    public static func inspect(path: String) -> RepositoryInsights {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return .empty }

        var files = 0
        var lines = 0
        var bytes: Int64 = 0
        var languageCounts: [String: Int] = [:]
        var names = Set<String>()
        var relativePaths = Set<String>()

        for case let url as URL in enumerator {
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
            names.insert(url.lastPathComponent)
            relativePaths.insert(String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            guard let language = languageByExtension[url.pathExtension.lowercased()] else { continue }
            languageCounts[language, default: 0] += 1
            if (values.fileSize ?? 0) <= 1_000_000,
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                lines += text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
            }
        }

        var capabilities: [String] = []
        if names.contains("package.json") { capabilities.append("Frontend / Node") }
        if names.contains("Package.swift") { capabilities.append("Swift nativo") }
        if names.contains("CMakeLists.txt") || names.contains("Makefile") { capabilities.append("C++ / Cubo") }
        if names.contains("prisma") || names.contains("schema.prisma") { capabilities.append("Base de datos") }
        if names.contains("docker-compose.yml") || names.contains("Dockerfile") { capabilities.append("Contenedores") }
        if capabilities.isEmpty { capabilities.append("Repositorio genérico") }

        let languages = languageCounts
            .map { LanguageMetric(name: $0.key, files: $0.value) }
            .sorted { $0.files == $1.files ? $0.name < $1.name : $0.files > $1.files }

        let hasLogin = relativePaths.contains(where: { $0.localizedCaseInsensitiveContains("auth") })
        let hasDatabase = names.contains("schema.prisma") || names.contains("database.ts") || names.contains("database.sql")
        let usernames = hasLogin && hasDatabase ? localChoisysUsernames() : []

        return RepositoryInsights(
            fileCount: files,
            sourceLines: lines,
            bytes: bytes,
            languages: Array(languages.prefix(8)),
            capabilities: capabilities,
            blenderAvailable: manager.fileExists(atPath: "/Applications/Blender.app"),
            abletonAvailable: manager.fileExists(atPath: "/Applications/Ableton Live 12 Lite.app") ||
                manager.fileExists(atPath: "/Applications/Ableton Live 11 Lite.app"),
            hasLogin: hasLogin,
            hasDatabase: hasDatabase,
            usernames: usernames
        )
    }

    private static func localChoisysUsernames() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".choisys/auth-v1.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return usernames(from: data)
    }

    public static func usernames(from data: Data) -> [String] {
        guard data.count <= 2 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 1,
              let accounts = root["accounts"] as? [[String: Any]] else { return [] }
        let names = accounts.compactMap { account -> String? in
            guard let profile = account["profile"] as? [String: Any],
                  let raw = profile["displayName"] as? String else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 120,
                  value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return value
        }
        return Array(Set(names)).sorted().prefix(200).map { $0 }
    }
}

public enum DiagnosticState: Sendable {
    case ready, running, passed(String), failed(String)

    public var label: String {
        switch self {
        case .ready: "Preparado"
        case .running: "Comprobando…"
        case .passed(let detail): "Correcto · \(detail)"
        case .failed(let detail): "Sin confirmar · \(detail)"
        }
    }
}

public struct RepositoryDiagnostic: Identifiable, Sendable {
    public enum Kind: Sendable { case files([String]), loopback(URL) }
    public let id: String
    public let title: String
    public let detail: String
    public let kind: Kind

    public init(id: String, title: String, detail: String, kind: Kind) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
    }
}

public enum DiagnosticCatalog {
    public static func diagnostics(for path: String) -> [RepositoryDiagnostic] {
        let root = URL(fileURLWithPath: path)
        func exists(_ candidates: [String]) -> RepositoryDiagnostic.Kind {
            .files(candidates.map { root.appendingPathComponent($0).path })
        }
        return [
            RepositoryDiagnostic(id: "api", title: "API local", detail: "Sonda HTTP sin cuerpo a 127.0.0.1:8765", kind: .loopback(URL(string: "http://127.0.0.1:8765/health")!)),
            RepositoryDiagnostic(id: "back", title: "Backend", detail: "Comprueba puntos de entrada conocidos", kind: exists(["server", "src/api", "apps/api", "api", "package.json"])),
            RepositoryDiagnostic(id: "front", title: "Frontend", detail: "Comprueba clientes web o nativos", kind: exists(["src", "app", "apps/mobile", "apple", "index.html"])),
            RepositoryDiagnostic(id: "cube", title: "Cubo", detail: "Comprueba contrato y fuentes C++", kind: exists(["src/core/cube.hpp", "include/scenarys/neo_cube.h", "CMakeLists.txt", "Makefile"])),
        ]
    }

    public static func run(_ diagnostic: RepositoryDiagnostic) async -> DiagnosticState {
        switch diagnostic.kind {
        case .files(let paths):
            let matches = paths.filter { FileManager.default.fileExists(atPath: $0) }
            return matches.isEmpty ? .failed("no se encontró un punto de entrada") : .passed("\(matches.count) evidencia(s)")
        case .loopback(let url):
            var request = URLRequest(url: url, timeoutInterval: 2)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failed("respuesta no HTTP") }
                return .passed("HTTP \(http.statusCode), servicio alcanzable")
            } catch {
                return .failed("servicio local no alcanzable")
            }
        }
    }
}
