import Foundation

public enum AlertLevel: String, Codable, Sendable, Comparable {
    case info, warning, critical
    var rank: Int { switch self { case .info: 0; case .warning: 1; case .critical: 2 } }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct DaemonAlert: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let level: AlertLevel
    public let title: String
    public let detail: String
    public let provenance: Provenance
}

/// Estado observado de un servicio declarado en una máquina concreta.
public struct ServiceStatus: Codable, Sendable, Hashable, Identifiable {
    public let definition: ServiceDefinition
    public let machine: MachineRole
    public let endpoint: String?
    public let probe: ProbeResult?
    public let listener: ListeningSocket?
    public let stats: LatencyStats
    public let note: String?

    public init(definition: ServiceDefinition, machine: MachineRole, endpoint: String?, probe: ProbeResult?,
                listener: ListeningSocket?, stats: LatencyStats, note: String?) {
        self.definition = definition; self.machine = machine; self.endpoint = endpoint; self.probe = probe
        self.listener = listener; self.stats = stats; self.note = note
    }

    public var id: String { definition.id + "@" + machine.rawValue }
    public var evidence: Evidence { probe?.evidence ?? .unverified }
    public var alive: Bool { probe?.reachable == true }
    public var label: String {
        guard let probe else { return note ?? "no verificado" }
        return probe.reachable ? probe.summary : probe.detail
    }
}

public struct NeonReport: Codable, Sendable, Hashable {
    public let ok: Bool?
    public let flags: [String: Bool]
    public let errorCode: String?
    public let durationMs: Int
    public let evidence: Evidence
    public let provenance: Provenance

    /// Proyección segura de la salida de `npm run check:neon`: solo booleanos
    /// y un código de error con forma de identificador.
    public static func parse(_ output: String, durationMs: Int, observedAt: Date = Date()) -> NeonReport {
        let provenance = Provenance(source: "choisys scripts/check-neon.mts", method: "transacción PostgreSQL de solo lectura", observedAt: observedAt)
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("{") }),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return NeonReport(ok: nil, flags: [:], errorCode: "NO_REPORT", durationMs: durationMs, evidence: .unverified, provenance: provenance)
        }
        var flags: [String: Bool] = [:]
        for (key, value) in object where key != "ok" { if let flag = value as? Bool { flags[key] = flag } }
        let code = (object["errorCode"] as? String).flatMap { $0.range(of: "^[A-Z0-9_]{1,64}$", options: .regularExpression) != nil ? $0 : nil }
        let ok = object["ok"] as? Bool
        return NeonReport(ok: ok, flags: flags, errorCode: code, durationMs: durationMs,
                          evidence: ok == true ? .verified : (flags["connected"] == true ? .partial : .failed), provenance: provenance)
    }
}

public struct PathHop: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let evidence: Evidence
    public let detail: String
}

public struct EcosystemSnapshot: Codable, Sendable {
    public let observedAt: Date
    public let machine: MachineSnapshot?
    public let ports: [ListeningSocket]
    public let portsEvidence: Evidence
    public let tailnet: TailnetSnapshot
    public let services: [ServiceStatus]
    public let neon: NeonReport?
    public let cubeExposure: ExposureVerdict
    public let tunnelActive: Bool
    public let alerts: [DaemonAlert]
    public let durationMs: Int

    public init(observedAt: Date, machine: MachineSnapshot?, ports: [ListeningSocket], portsEvidence: Evidence, tailnet: TailnetSnapshot,
                services: [ServiceStatus], neon: NeonReport?, cubeExposure: ExposureVerdict, tunnelActive: Bool, alerts: [DaemonAlert], durationMs: Int) {
        self.observedAt = observedAt; self.machine = machine; self.ports = ports; self.portsEvidence = portsEvidence; self.tailnet = tailnet
        self.services = services; self.neon = neon; self.cubeExposure = cubeExposure; self.tunnelActive = tunnelActive
        self.alerts = alerts; self.durationMs = durationMs
    }

    public func status(_ id: String) -> [ServiceStatus] { services.filter { $0.definition.id == id } }
    public func best(_ id: String) -> ServiceStatus? {
        status(id).max { ($0.alive ? 1 : 0, $0.machine == .mac ? 1 : 0) < ($1.alive ? 1 : 0, $1.machine == .mac ? 1 : 0) }
    }

    /// Ruta cliente → frontend → API → DB → Cubo con el primer eslabón roto.
    public var productPath: [PathHop] {
        func hop(_ id: String, _ name: String) -> PathHop {
            if id == "neon" {
                guard let neon else { return PathHop(id: id, name: name, evidence: .unverified, detail: "sin diagnóstico (pide «comprueba Neon»)") }
                return PathHop(id: id, name: name, evidence: neon.evidence, detail: neon.ok == true ? "lectura correcta · \(neon.durationMs) ms" : (neon.errorCode ?? "incompleto"))
            }
            guard let status = best(id) else { return PathHop(id: id, name: name, evidence: .unverified, detail: "no declarado") }
            return PathHop(id: id, name: "\(name) · \(status.machine.label)", evidence: status.evidence, detail: status.label)
        }
        return [hop("landing", "Cliente / landing"), hop("choisys-web", "Frontend choisys"), hop("choisys-api", "API"), hop("neon", "Neon"), hop("neo-cube", "Cubo")]
    }

    public var firstBrokenHop: PathHop? { productPath.first { $0.evidence == .failed } }
}

#if os(macOS)
public enum EcosystemProbe {
    /// Observa todo el entorno en paralelo. Solo lecturas automáticas.
    public static func observe(config: TopologyConfig = .load(), previousNeon: NeonReport? = nil) async -> EcosystemSnapshot {
        let started = Date()
        async let portsTask = PortProbe.listening()
        async let tailnetTask = TailnetProbe.status()
        let machine = SystemProbe.machine()
        let ports = await portsTask
        let tailnet = await tailnetTask
        let desktop = tailnet.peer(named: config.desktopHost)

        var services: [ServiceStatus] = []
        await withTaskGroup(of: ServiceStatus?.self) { group in
            for definition in config.services {
                for machine in definition.machines {
                    group.addTask { await probe(definition, on: machine, ports: ports.sockets, desktop: desktop) }
                }
            }
            for await status in group { if let status { services.append(status) } }
        }
        services.sort { ($0.definition.id, $0.machine.rawValue) < ($1.definition.id, $1.machine.rawValue) }

        // Exposición del Cubo: bindings locales + sonda TCP a la IP de tailnet del Desktop.
        let cubeBindings = ports.sockets.filter { $0.port == 8765 }.map { (address: $0.address, port: $0.port) }
        let exposure = CoreBridge.checkExposure(cubeBindings, complete: ports.evidence == .verified)
        let tunnel = ports.sockets.contains { $0.port == 8765 && $0.command.lowercased().hasPrefix("ssh") && $0.scope == .loopback }

        var alerts: [DaemonAlert] = []
        let provenance = Provenance(source: "lsof", method: "listeners TCP :8765")
        if exposure.exposed {
            alerts.append(DaemonAlert(id: "cube-exposed-local", level: .critical, title: "Cubo expuesto en este Mac",
                                      detail: "El puerto 8765 escucha fuera de 127.0.0.1 (\(exposure.reason)). Debe ser solo loopback.", provenance: provenance))
        }
        if let desktopCube = services.first(where: { $0.definition.id == "neo-cube" && $0.machine == .desktop }), desktopCube.alive {
            alerts.append(DaemonAlert(id: "cube-exposed-tailnet", level: .critical, title: "Cubo del Desktop accesible por la tailnet",
                                      detail: "\(desktopCube.endpoint ?? "8765") acepta conexiones TCP. Debe escuchar solo en 127.0.0.1 y llegar por túnel SSH.",
                                      provenance: desktopCube.probe?.provenance ?? provenance))
        }
        var systemListeners: [ListeningSocket] = []
        for socket in ports.sockets where socket.scope >= .allInterfaces || socket.scope == .publicNetwork {
            let known = config.services.first { $0.port == socket.port }
            if known?.loopbackOnly == true { continue }
            guard known != nil || socket.isDevelopmentProcess else { systemListeners.append(socket); continue }
            alerts.append(DaemonAlert(id: "exposed-\(socket.id)", level: .warning, title: ":\(socket.port) escucha en \(socket.scope.label)",
                                      detail: "\(socket.command) (PID \(socket.pid)) en \(socket.address). \(known.map { "Servicio \($0.name): visible fuera de este Mac." } ?? "Proceso de desarrollo no declarado.")",
                                      provenance: ports.provenance))
        }
        if !systemListeners.isEmpty {
            let names = Array(Set(systemListeners.map { $0.knownLabel ?? $0.command })).sorted().joined(separator: ", ")
            alerts.append(DaemonAlert(id: "system-listeners", level: .info, title: "\(systemListeners.count) listeners del sistema en todas las interfaces",
                                      detail: "\(names). No son servicios de Scenarys; revisa en Ajustes del Sistema si no los necesitas.", provenance: ports.provenance))
        }
        if !tailnet.running {
            alerts.append(DaemonAlert(id: "tailnet", level: .info, title: "Tailnet no verificada",
                                      detail: tailnet.error ?? "Tailscale: \(tailnet.backendState)", provenance: tailnet.provenance))
        }
        if machine.thermalState == "alto" || machine.thermalState == "crítico" {
            alerts.append(DaemonAlert(id: "thermal", level: .warning, title: "Temperatura \(machine.thermalState)",
                                      detail: "macOS informa estrés térmico; los builds irán más lentos.", provenance: machine.provenance))
        }
        alerts.sort { $0.level > $1.level }

        let snapshot = EcosystemSnapshot(observedAt: started, machine: machine, ports: ports.sockets, portsEvidence: ports.evidence,
                                         tailnet: tailnet, services: services, neon: previousNeon ?? DaemonStore.read(NeonReport.self, from: "snapshots/neon.json"),
                                         cubeExposure: exposure, tunnelActive: tunnel, alerts: alerts,
                                         durationMs: Int(Date().timeIntervalSince(started) * 1000))
        DaemonStore.write(snapshot, to: "snapshots/ecosystem.json")
        return snapshot
    }

    static func probe(_ definition: ServiceDefinition, on machine: MachineRole, ports: [ListeningSocket], desktop: TailnetPeer?) async -> ServiceStatus? {
        let key = definition.id + "@" + machine.rawValue
        func status(_ endpoint: String?, _ probe: ProbeResult?, listener: ListeningSocket? = nil, note: String? = nil) async -> ServiceStatus {
            if let probe { await LatencyHistory.shared.record(key, probe) }
            return ServiceStatus(definition: definition, machine: machine, endpoint: endpoint, probe: probe, listener: listener,
                                 stats: await LatencyHistory.shared.stats(key), note: note)
        }
        switch machine {
        case .external:
            if let raw = definition.url, let url = URL(string: raw) { return await status(raw, await NetworkProbe.http(url, timeout: 5)) }
            return await status(nil, nil, note: definition.id == "neon" ? "diagnóstico bajo demanda (choisys check:neon)" : nil)
        case .mac:
            guard let port = definition.port else { return nil }
            let listener = ports.first { $0.port == port }
            guard listener != nil else { return await status("127.0.0.1:\(port)", nil, note: "sin listener en :\(port)") }
            let url = URL(string: "http://127.0.0.1:\(port)\(definition.healthPath ?? "/")")!
            return await status(url.absoluteString, await NetworkProbe.http(url), listener: listener)
        case .desktop:
            guard let port = definition.port else { return nil }
            guard let desktop, let ip = desktop.ipv4 else { return await status(nil, nil, note: "Desktop no visible en la tailnet") }
            guard desktop.online else { return await status("\(ip):\(port)", nil, note: "Desktop desconectado de la tailnet") }
            if definition.loopbackOnly {
                // Solo comprobamos que NO acepta conexiones por la tailnet.
                let probe = await NetworkProbe.tcp(host: ip, port: port, timeout: 1.5)
                guard !probe.reachable else { return await status("\(ip):\(port)", probe) }
                // Cerrado por la tailnet es lo correcto: contrato verificado, salud del Cubo sin medir.
                let contract = ProbeResult(target: probe.target, reachable: false, statusCode: nil, latencyMs: nil, evidence: .partial,
                                           detail: "no expuesto en la tailnet ✓ · salud: túnel", provenance: probe.provenance)
                return ServiceStatus(definition: definition, machine: machine, endpoint: "\(ip):\(port)", probe: contract, listener: nil,
                                     stats: await LatencyHistory.shared.stats(key), note: nil)
            }
            // Por nombre MagicDNS (*.ts.net): ATS lo permite por excepción; una IP literal no.
            let host = desktop.dnsName.isEmpty ? ip : desktop.dnsName
            let url = URL(string: "http://\(host):\(port)\(definition.healthPath ?? "/")")!
            return await status(url.absoluteString, await NetworkProbe.http(url, timeout: 4))
        case .iphone:
            return nil
        }
    }

    /// Diagnóstico de Neon delegando en el script de solo lectura de choisys.
    /// Requiere confirmación: lanza Node con la configuración local de Neo.
    public static func checkNeon(config: TopologyConfig = .load()) async -> NeonReport {
        let repo = config.expandedWorkspaceRoot + "/choisys/repo"
        let started = Date()
        do {
            let result = try await CommandRunner.run("npm", ["run", "--silent", "check:neon"], in: repo, timeout: 40, approval: .userConfirmed)
            let report = NeonReport.parse(result.standardOutput, durationMs: result.durationMs, observedAt: started)
            DaemonStore.write(report, to: "snapshots/neon.json")
            return report
        } catch {
            return NeonReport(ok: nil, flags: [:], errorCode: "CHECK_NOT_RUN", durationMs: 0, evidence: .unverified,
                              provenance: Provenance(source: "choisys", method: error.localizedDescription, observedAt: started))
        }
    }
}
#endif
