import Foundation

/// Procedencia del código de un servicio. Es metadata: no es la ubicación
/// del servicio y nunca se dibuja como un nodo runtime.
public struct SourceRepository: Sendable, Hashable, Codable {
    public let name: String
    public let localPath: String?
    public let remote: String?
    public let remoteVerified: Bool

    public init(name: String, localPath: String?, remote: String?, remoteVerified: Bool) {
        self.name = name
        self.localPath = localPath
        self.remote = remote
        self.remoteVerified = remoteVerified
    }
}

public enum Transport: String, Sendable, Hashable {
    case tailscale, https, loopback, ssh, internet, postgres, observation, source

    public var label: String {
        switch self {
        case .tailscale: "Tailscale"
        case .https: "HTTPS"
        case .loopback: "loopback"
        case .ssh: "SSH"
        case .internet: "Internet"
        case .postgres: "PostgreSQL/TLS"
        case .observation: "observación"
        case .source: "código"
        }
    }
}

public struct RuntimeMachine: Identifiable, Sendable, Hashable {
    public let id: String
    public let role: MachineRole
    public let name: String
    public let address: String?
    public let state: Evidence
    public let detail: String
}

/// Un componente que se está ejecutando (o que debería y no responde).
public struct RuntimeService: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case daemon, service, engine, external, process }
    public let id: String
    public let name: String
    public let kind: Kind
    public let host: MachineRole
    public let port: UInt16?
    public let bind: String?
    public let bindEvidence: String
    public let published: String?
    public let protocolName: String
    public let state: Evidence
    public let health: String
    public let latencyMs: Int?
    public let pid: Int?
    public let uptime: String?
    public let lastCheck: Date?
    public let source: SourceRepository?
    public let technologies: [String]
    public let warning: String?
}

public struct RuntimeLink: Identifiable, Sendable, Hashable {
    public let from: String
    public let to: String
    public let transport: Transport
    public let label: String
    public let state: Evidence
    public let warning: String?
    public let provenanceOnly: Bool
    public var id: String { from + "→" + to + ":" + label }
}

/// Topología de ejecución: qué máquinas existen, qué corre en cada una, qué
/// responde y qué conexiones están verificadas. El sistema de archivos solo
/// aporta metadata de procedencia.
public struct RuntimeTopology: Sendable {
    public let machines: [RuntimeMachine]
    public let services: [RuntimeService]
    public let links: [RuntimeLink]
    public let observedAt: Date
    /// Aviso global cuando una parte del mapa no se puede medir (p. ej. Tailscale parado).
    public let notice: String?

    public func service(_ id: String) -> RuntimeService? { services.first { $0.id == id } }
    public func services(on host: MachineRole) -> [RuntimeService] { services.filter { $0.host == host } }

    /// Repositorio de GitHub de cada fuente conocida (declarado hasta verificarlo con git).
    static let declaredRemotes = ["choisys": "choisys", "cubo-de-neo": "neos-cube", "scenarys": "scenarys",
                                  "daemon-core": "daemon-core", "neo-cube-web": "neo-cube-web"]

    public static func source(_ repository: String?, config: TopologyConfig, catalog: [RepositorySnapshot],
                              verified: [String: SourceRepository]) -> SourceRepository? {
        guard let repository else { return nil }
        if let known = verified[repository] { return known }
        let local = catalog.first { $0.name == repository }?.path
        let remote = declaredRemotes[repository].map { "github.com/\(config.githubOwner)/\($0)" }
        return SourceRepository(name: repository, localPath: local, remote: remote, remoteVerified: false)
    }

    public static func build(_ snapshot: EcosystemSnapshot, config: TopologyConfig, catalog: [RepositorySnapshot] = [],
                             sources: [String: SourceRepository] = [:]) -> RuntimeTopology {
        var machines: [RuntimeMachine] = []
        var services: [RuntimeService] = []
        var links: [RuntimeLink] = []
        let tailnet = snapshot.tailnet
        let desktopPeer = tailnet.peer(named: config.desktopHost)

        // Máquinas: este Mac siempre; el resto solo si la tailnet las ve.
        let machine = snapshot.machine
        machines.append(RuntimeMachine(id: "m:mac", role: .mac, name: "MacBook", address: tailnet.me?.ipv4, state: .verified,
                                       detail: machine.map { "\($0.model) · carga \(String(format: "%.2f", $0.loadAverage.first ?? 0)) · \($0.thermalState)" } ?? "este Mac"))
        if let desktopPeer {
            machines.append(RuntimeMachine(id: "m:desktop", role: .desktop, name: "Desktop", address: desktopPeer.ipv4,
                                           state: desktopPeer.online ? .verified : .failed,
                                           detail: "\(desktopPeer.shortName) · \(desktopPeer.online ? "en línea" : "desconectado") · host operativo"))
        } else {
            // El PC existe aunque no se pueda medir: se dibuja como DESCONOCIDO, no se oculta.
            machines.append(RuntimeMachine(id: "m:desktop", role: .desktop, name: "Desktop", address: nil, state: .unverified,
                                           detail: tailnet.running ? "no aparece en la tailnet · host operativo" : "sin medir: Tailscale parado en este Mac · host operativo"))
        }
        for (index, phone) in tailnet.peers.filter({ !$0.isSelf && $0.os.lowercased() == "ios" }).prefix(2).enumerated() {
            machines.append(RuntimeMachine(id: "m:iphone\(index)", role: .iphone, name: "iPhone", address: phone.ipv4,
                                           state: phone.online ? .verified : .unverified, detail: "\(phone.shortName) · \(phone.online ? "en línea" : "desconectado")"))
        }

        func source(_ repository: String?) -> SourceRepository? { Self.source(repository, config: config, catalog: catalog, verified: sources) }

        // Daemon: está corriendo, porque es quien observa.
        services.append(RuntimeService(id: "s:daemon", name: "Daemon", kind: .daemon, host: .mac, port: nil, bind: nil, bindEvidence: "proceso local",
                                       published: nil, protocolName: "app nativa", state: .verified, health: "observando",
                                       latencyMs: nil, pid: Int(ProcessInfo.processInfo.processIdentifier), uptime: nil, lastCheck: snapshot.observedAt,
                                       source: source("daemon-core"), technologies: ["SwiftUI", "C++20"], warning: nil))

        // Servicios del Mac: solo si hay un listener real.
        for status in snapshot.services where status.machine == .mac {
            guard let listener = status.listener else { continue }
            let definition = status.definition
            services.append(RuntimeService(id: "s:\(status.id)", name: definition.name, kind: definition.role == .engine ? .engine : .service,
                                           host: .mac, port: listener.port, bind: listener.address, bindEvidence: "medido con lsof",
                                           published: nil, protocolName: "HTTP", state: status.evidence, health: status.label,
                                           latencyMs: status.probe?.latencyMs, pid: listener.pid, uptime: listener.elapsed, lastCheck: status.probe?.provenance.observedAt,
                                           source: source(definition.repository), technologies: definition.technologies,
                                           warning: definition.loopbackOnly && listener.scope != .loopback ? "escucha fuera de loopback" : nil))
        }
        // Procesos de desarrollo del Mac que no están declarados.
        let declaredPorts = Set(config.services.compactMap(\.port))
        for socket in snapshot.ports where socket.isDevelopmentProcess && !declaredPorts.contains(socket.port) && socket.command.lowercased() != "daemon" {
            guard !services.contains(where: { $0.host == .mac && $0.port == socket.port }) else { continue }
            services.append(RuntimeService(id: "s:mac-\(socket.port)", name: "\(socket.command) :\(socket.port)", kind: .process, host: .mac,
                                           port: socket.port, bind: socket.address, bindEvidence: "medido con lsof", published: nil, protocolName: "TCP",
                                           state: .verified, health: "escuchando", latencyMs: nil, pid: socket.pid, uptime: socket.elapsed,
                                           lastCheck: snapshot.observedAt, source: nil, technologies: [],
                                           warning: socket.scope >= .allInterfaces ? "escucha en todas las interfaces" : nil))
        }

        // Servicios del Desktop: por su ruta publicada (Serve) y sus puertos.
        if desktopPeer != nil {
            for status in snapshot.services where status.machine == .desktop {
                let definition = status.definition
                if definition.loopbackOnly {
                    let exposed = status.alive
                    services.append(RuntimeService(id: "s:\(status.id)", name: definition.name, kind: .engine, host: .desktop, port: definition.port,
                                                   bind: "127.0.0.1", bindEvidence: exposed ? "¡acepta conexiones por la tailnet!" : "cerrado por la tailnet (medido)",
                                                   published: nil, protocolName: "HTTP + Bearer", state: exposed ? .failed : .unverified,
                                                   health: exposed ? "EXPUESTO" : "aislado · salud solo vía API", latencyMs: nil, pid: nil, uptime: nil,
                                                   lastCheck: status.probe?.provenance.observedAt, source: source(definition.repository),
                                                   technologies: definition.technologies, warning: exposed ? "contrato de aislamiento roto" : nil))
                    continue
                }
                guard status.probe != nil else { continue }
                let direct = status.note?.hasPrefix("también abierto directo") == true
                services.append(RuntimeService(id: "s:\(status.id)", name: definition.name, kind: .service, host: .desktop, port: definition.port,
                                               bind: direct ? "tailnet + loopback" : "127.0.0.1 (según config del PC)",
                                               bindEvidence: direct ? "el puerto responde directo por la tailnet (medido)" : "no responde directo por la tailnet",
                                               published: status.endpoint, protocolName: "HTTPS (Tailscale Serve)", state: status.evidence,
                                               health: status.label, latencyMs: status.probe?.latencyMs, pid: nil, uptime: nil,
                                               lastCheck: status.probe?.provenance.observedAt, source: source(definition.repository),
                                               technologies: definition.technologies, warning: direct ? ":\(definition.port.map(String.init) ?? "?") abierto directo además de Serve" : nil))
            }
        }

        // Externos.
        for status in snapshot.services where status.machine == .external {
            let definition = status.definition
            var name = definition.name
            var technologies = definition.technologies
            var state = status.evidence
            var health = status.label
            if definition.id == "neon" {
                state = snapshot.neon?.evidence ?? .unverified
                health = snapshot.neon.map { $0.ok == true ? "lectura correcta · \($0.durationMs) ms" : ($0.errorCode ?? "incompleto") } ?? "sin diagnóstico"
            }
            if let server = status.probe?.server, server.lowercased().contains("github") {
                name += " · GitHub Pages"
                technologies.append("GitHub Pages (cabecera Server medida)")
            }
            services.append(RuntimeService(id: "s:\(status.id)", name: name, kind: .external, host: .external, port: nil, bind: nil, bindEvidence: "",
                                           published: status.endpoint, protocolName: definition.id == "neon" ? "PostgreSQL/TLS" : "HTTPS",
                                           state: state, health: health, latencyMs: status.probe?.latencyMs, pid: nil, uptime: nil,
                                           lastCheck: status.probe?.provenance.observedAt ?? snapshot.neon?.provenance.observedAt,
                                           source: definition.id == "website" ? source("scenarys") : nil, technologies: technologies, warning: nil))
        }

        // Conexiones.
        let hub = "n:tailnet"
        for machine in machines {
            links.append(RuntimeLink(from: machine.id, to: hub, transport: .tailscale, label: machine.address ?? "",
                                     state: tailnet.running ? machine.state : .unverified, warning: nil, provenanceOnly: false))
        }
        let desktopMeasured = services.contains { $0.host == .desktop && $0.kind == .service }
        for external in services where external.host == .external && !desktopMeasured && external.id != "s:github@external" && external.id != "s:neon@external" {
            links.append(RuntimeLink(from: "s:daemon", to: external.id, transport: .observation, label: "sonda", state: external.state, warning: nil, provenanceOnly: false))
        }
        func has(_ id: String) -> Bool { services.contains { $0.id == id } }
        let api = services.first { $0.host == .desktop && $0.id.hasPrefix("s:choisys-api") } ?? services.first { $0.id.hasPrefix("s:choisys-api") }
        let web = services.first { $0.host == .desktop && $0.id.hasPrefix("s:choisys-web") } ?? services.first { $0.id.hasPrefix("s:choisys-web") }
        let cube = services.first { $0.host == .desktop && $0.kind == .engine } ?? services.first { $0.kind == .engine }
        if let api, let web {
            links.append(RuntimeLink(from: web.id, to: api.id, transport: .https, label: ":8443", state: Evidence.weakest([web.state, api.state]), warning: nil, provenanceOnly: false))
        }
        if let api, let cube {
            links.append(RuntimeLink(from: api.id, to: cube.id, transport: .loopback, label: "127.0.0.1:8765", state: cube.state == .failed ? .failed : .unverified,
                                     warning: cube.warning, provenanceOnly: false))
        }
        // Túnel SSH del Mac al Cubo: el socket local está medido; el extremo remoto solo responde con Bearer.
        if let cube, snapshot.tunnelActive {
            links.append(RuntimeLink(from: "m:mac", to: cube.id, transport: .ssh, label: "túnel 127.0.0.1:8765", state: .partial, warning: nil, provenanceOnly: false))
        }
        if let api, has("s:neon@external") {
            links.append(RuntimeLink(from: api.id, to: "s:neon@external", transport: .postgres, label: "Prisma", state: snapshot.neon?.evidence ?? .unverified, warning: nil, provenanceOnly: false))
        }
        for service in [api, web].compactMap({ $0 }) where service.warning != nil && service.host == .desktop {
            links.append(RuntimeLink(from: hub, to: service.id, transport: .tailscale, label: ":\(service.port.map(String.init) ?? "?") directo", state: .partial,
                                     warning: service.warning, provenanceOnly: false))
        }
        if let api, has("s:website@external") {
            links.append(RuntimeLink(from: "s:website@external", to: api.id, transport: .internet, label: "Funnel :8443 (declarado)", state: .unverified, warning: nil, provenanceOnly: false))
        }
        if has("s:github@external") {
            let github = services.first { $0.id == "s:github@external" }
            links.append(RuntimeLink(from: "m:mac", to: "s:github@external", transport: .https, label: "git / gh", state: github?.state ?? .unverified, warning: nil, provenanceOnly: false))
        }
        // Procedencia (solo si se activa): servicio → repo → GitHub.
        var repos: [String: SourceRepository] = [:]
        for service in services { if let source = service.source { repos[source.name] = source } }
        for service in services {
            if let source = service.source {
                links.append(RuntimeLink(from: service.id, to: "r:\(source.name)", transport: .source, label: "fuente", state: .verified, warning: nil, provenanceOnly: true))
            }
        }
        for repo in repos.values where repo.remote != nil {
            links.append(RuntimeLink(from: "r:\(repo.name)", to: "s:github@external", transport: .source, label: repo.remoteVerified ? "remote" : "remote (declarado)",
                                     state: repo.remoteVerified ? .verified : .unverified, warning: nil, provenanceOnly: true))
        }
        let notice: String? = !tailnet.running
            ? "Tailscale está parado en este Mac: el PC, el iPhone y el Cubo no se pueden medir. Actívalo para ver la topología completa."
            : (desktopPeer == nil ? "El PC no aparece en la tailnet." : nil)
        return RuntimeTopology(machines: machines, services: services, links: links, observedAt: snapshot.observedAt, notice: notice)
    }

    public var repositories: [SourceRepository] {
        var seen: [String: SourceRepository] = [:]
        for service in services { if let source = service.source { seen[source.name] = source } }
        return seen.values.sorted { $0.name < $1.name }
    }
}
