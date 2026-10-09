import Foundation

public struct ToolInfo: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let category: String
    public let purpose: String
    public let path: String?
    public let version: String?
    public let license: String?
    public let licenseSource: String?
    public let evidence: Evidence
    public let provenance: Provenance
    public var id: String { name }
    public var installed: Bool { path != nil }
}

public struct ToolchainSnapshot: Codable, Sendable {
    public let tools: [ToolInfo]
    public let observedAt: Date
    public func tool(_ name: String) -> ToolInfo? { tools.first { $0.name.lowercased() == name.lowercased() } }
}

public enum VersionParser {
    /// Primera versión semántica que aparece en la salida de `--version`.
    public static func first(_ text: String) -> String? {
        guard let range = text.range(of: #"\d+\.\d+(\.\d+)?([.-][0-9A-Za-z]+)?"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    /// `brew info --json=v2 --installed` → nombre → (versión, licencia SPDX).
    public static func brewFormulae(_ data: Data) -> [String: (version: String?, license: String?)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: (String?, String?)] = [:]
        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String else { continue }
            let installed = (formula["installed"] as? [[String: Any]])?.first?["version"] as? String
            result[name] = (installed, formula["license"] as? String)
        }
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            result[token] = (cask["installed"] as? String, nil)
        }
        return result
    }
}

#if os(macOS)
public enum ToolchainProbe {
    struct Declared: Sendable {
        let name: String; let binary: String?; let app: String?; let brew: String?; let category: String; let purpose: String
        let versionArguments: [String]
    }

    static let declared: [Declared] = [
        .init(name: "Xcode", binary: nil, app: "/Applications/Xcode.app", brew: nil, category: "Apple", purpose: "SDKs, simulador e iOS", versionArguments: []),
        .init(name: "Swift", binary: "swift", app: nil, brew: nil, category: "Apple", purpose: "DaemonKit y app nativa", versionArguments: ["--version"]),
        .init(name: "clang", binary: "clang", app: nil, brew: nil, category: "Apple", purpose: "núcleo C++20 de Daemon y Cubo", versionArguments: ["--version"]),
        .init(name: "Git", binary: "git", app: nil, brew: "git", category: "Control de versiones", purpose: "estado de repos (núcleo C++)", versionArguments: ["--version"]),
        .init(name: "GitHub CLI", binary: "gh", app: nil, brew: "gh", category: "Control de versiones", purpose: "PRs, issues y Actions", versionArguments: ["--version"]),
        .init(name: "Homebrew", binary: "brew", app: nil, brew: nil, category: "Paquetes", purpose: "gestor de herramientas open source", versionArguments: ["--version"]),
        .init(name: "Node", binary: "node", app: nil, brew: "node", category: "Web", purpose: "choisys API, Expo y landing", versionArguments: ["--version"]),
        .init(name: "npm", binary: "npm", app: nil, brew: nil, category: "Web", purpose: "scripts de choisys (check:neon)", versionArguments: ["--version"]),
        .init(name: "CMake", binary: "cmake", app: nil, brew: "cmake", category: "Build", purpose: "tests C++ (ctest)", versionArguments: ["--version"]),
        .init(name: "jq", binary: "jq", app: nil, brew: "jq", category: "CLI", purpose: "JSON en scripts .command", versionArguments: ["--version"]),
        .init(name: "OpenSSH", binary: "ssh", app: nil, brew: nil, category: "Red", purpose: "túnel cifrado al Cubo del Desktop", versionArguments: ["-V"]),
        .init(name: "Tailscale", binary: "tailscale", app: "/Applications/Tailscale.app", brew: nil, category: "Red", purpose: "tailnet privada Mac ↔ Desktop ↔ iPhone", versionArguments: ["version"]),
        .init(name: "VS Code", binary: "code", app: "/Applications/Visual Studio Code.app", brew: nil, category: "Editor", purpose: "edición", versionArguments: []),
        .init(name: "Blender", binary: nil, app: "/Applications/Blender.app", brew: nil, category: "Creativo", purpose: "assets 3D exportados (no runtime)", versionArguments: []),
        .init(name: "Ableton Live Lite", binary: nil, app: "/Applications/Ableton Live 12 Lite.app", brew: nil, category: "Creativo", purpose: "experimentos audio-reactivos (no runtime)", versionArguments: []),
        .init(name: "Docker", binary: "docker", app: "/Applications/Docker.app", brew: nil, category: "Contenedores", purpose: "no usado por Daemon", versionArguments: ["--version"]),
        .init(name: "PostgreSQL client", binary: "psql", app: nil, brew: "libpq", category: "Datos", purpose: "no necesario: Neon vía Prisma", versionArguments: ["--version"]),
    ]

    public static func observe() async -> ToolchainSnapshot {
        let now = Date()
        var brew: [String: (version: String?, license: String?)] = [:]
        if let result = try? await CommandRunner.run("brew", ["info", "--json=v2", "--installed"], timeout: 25, maxOutputBytes: 16 * 1_048_576), result.succeeded {
            brew = VersionParser.brewFormulae(Data(result.standardOutput.utf8))
        }
        var tools: [ToolInfo] = []
        await withTaskGroup(of: ToolInfo.self) { group in
            for item in declared {
                let brewEntry = item.brew.flatMap { brew[$0] }
                group.addTask { await inspect(item, brew: brewEntry, at: now) }
            }
            for await tool in group { tools.append(tool) }
        }
        let order = Dictionary(uniqueKeysWithValues: declared.enumerated().map { ($1.name, $0) })
        tools.sort { (order[$0.name] ?? 0) < (order[$1.name] ?? 0) }
        let snapshot = ToolchainSnapshot(tools: tools, observedAt: now)
        DaemonStore.write(snapshot, to: "snapshots/toolchain.json")
        return snapshot
    }

    static func inspect(_ item: Declared, brew: (version: String?, license: String?)?, at now: Date) async -> ToolInfo {
        var path = item.binary.flatMap(Toolbox.locate)
        var version: String?
        var method = "no encontrado en rutas fijas"
        if let binary = item.binary, path != nil, !item.versionArguments.isEmpty,
           let result = try? await CommandRunner.run(binary, item.versionArguments, timeout: 6) {
            version = VersionParser.first(result.standardOutput + result.standardError)
            method = "\(binary) \(item.versionArguments.joined(separator: " "))"
        }
        if let app = item.app, FileManager.default.fileExists(atPath: app) {
            if path == nil { path = app }
            if version == nil, let bundle = Bundle(path: app) {
                version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                method = "Info.plist de \(URL(fileURLWithPath: app).lastPathComponent)"
            }
        }
        let license = brew?.license
        return ToolInfo(name: item.name, category: item.category, purpose: item.purpose, path: path,
                        version: version ?? brew?.version, license: license,
                        licenseSource: license != nil ? "Homebrew (brew info --json=v2)" : nil,
                        evidence: path == nil ? .unverified : (version == nil ? .partial : .verified),
                        provenance: Provenance(source: path ?? "rutas fijas", method: method, observedAt: now))
    }
}
#endif
