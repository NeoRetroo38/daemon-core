import Foundation

public enum MachineRole: String, Codable, Sendable, CaseIterable {
    case mac, desktop, iphone, external

    public var label: String {
        switch self { case .mac: "MacBook"; case .desktop: "Desktop Windows"; case .iphone: "iPhone"; case .external: "Externo" }
    }
}

public enum ServiceRole: String, Codable, Sendable {
    case landing, frontend, api, engine, database, forge, website
}

/// Servicio declarado. Declarado no significa conectado: su estado solo sale
/// de una sonda.
public struct ServiceDefinition: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let role: ServiceRole
    public let machines: [MachineRole]
    public let port: UInt16?
    public let healthPath: String?
    public let url: String?
    public let repository: String?
    public let technologies: [String]
    public let dependsOn: [String]
    /// Contrato de aislamiento: solo puede escuchar en 127.0.0.1.
    public let loopbackOnly: Bool
    /// Publicado a propósito en la tailnet (p. ej. demo remota).
    public let tailnetPublished: Bool
}

public struct TopologyConfig: Codable, Sendable {
    public var desktopHost: String
    public var desktopSSHUser: String?
    public var workspaceRoot: String
    public var githubOwner: String
    public var services: [ServiceDefinition]

    public static let standard = TopologyConfig(
        desktopHost: "desktop-dgjsrgv",
        desktopSSHUser: nil,
        workspaceRoot: "~/Desktop/scenarys",
        githubOwner: "NeoRetroo38",
        services: [
            ServiceDefinition(id: "landing", name: "Landing Scenarys", role: .landing, machines: [.mac], port: 5173, healthPath: "/", url: nil,
                              repository: "scenarys", technologies: ["Vite", "React", "TypeScript"], dependsOn: ["choisys-web"],
                              loopbackOnly: false, tailnetPublished: true),
            ServiceDefinition(id: "choisys-web", name: "choisys web", role: .frontend, machines: [.mac, .desktop], port: 8081, healthPath: "/", url: nil,
                              repository: "choisys", technologies: ["Expo", "React Native Web", "TypeScript"], dependsOn: ["choisys-api"],
                              loopbackOnly: false, tailnetPublished: true),
            ServiceDefinition(id: "choisys-api", name: "choisys API", role: .api, machines: [.mac, .desktop], port: 3000, healthPath: "/health", url: nil,
                              repository: "choisys", technologies: ["Node", "Express 5", "Prisma", "TypeScript"], dependsOn: ["neon", "neo-cube"],
                              loopbackOnly: false, tailnetPublished: true),
            ServiceDefinition(id: "neo-cube", name: "Cubo de Neo", role: .engine, machines: [.mac, .desktop], port: 8765, healthPath: "/health", url: nil,
                              repository: "cubo-de-neo", technologies: ["C++17", "sockets POSIX/Winsock"], dependsOn: [],
                              loopbackOnly: true, tailnetPublished: false),
            ServiceDefinition(id: "neon", name: "Neon PostgreSQL", role: .database, machines: [.external], port: nil, healthPath: nil, url: nil,
                              repository: "choisys", technologies: ["PostgreSQL", "Neon", "Prisma"], dependsOn: [],
                              loopbackOnly: false, tailnetPublished: false),
            ServiceDefinition(id: "github", name: "GitHub", role: .forge, machines: [.external], port: nil, healthPath: nil, url: "https://api.github.com/",
                              repository: nil, technologies: ["Git", "GitHub CLI"], dependsOn: [],
                              loopbackOnly: false, tailnetPublished: false),
            ServiceDefinition(id: "website", name: "neowebdevsolutions.com", role: .website, machines: [.external], port: nil, healthPath: nil,
                              url: "https://neowebdevsolutions.com/", repository: nil, technologies: ["HTTPS"], dependsOn: [],
                              loopbackOnly: false, tailnetPublished: false),
        ]
    )

    public var expandedWorkspaceRoot: String { (workspaceRoot as NSString).expandingTildeInPath }

    public func service(_ id: String) -> ServiceDefinition? { services.first { $0.id == id } }

    /// `~/Library/Application Support/Daemon/topology.json`. Se crea con los
    /// valores declarados la primera vez; Neo puede editarlo.
    public static func load() -> TopologyConfig {
        let url = DaemonStore.directory.appendingPathComponent("topology.json")
        if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(TopologyConfig.self, from: data) { return value }
        DaemonStore.write(standard, to: "topology.json")
        return standard
    }
}

/// Almacén local de Daemon (instantáneas, índice, topología). Nunca guarda
/// secretos, cuerpos de peticiones ni contenido de usuarios.
public enum DaemonStore {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("Daemon", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    public static func write<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    public static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
