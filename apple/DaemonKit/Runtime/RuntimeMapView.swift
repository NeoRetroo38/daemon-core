#if os(macOS)
import SwiftUI

/// Mapa vivo de ejecución: máquinas como anclas, servicios dentro de su
/// máquina y conexiones como protagonistas. Los repositorios solo aparecen
/// con «Mostrar procedencia del código».
public struct RuntimeMapView: View {
    let topology: RuntimeTopology
    @Binding var selection: String?
    @Binding var showProvenance: Bool
    var compact: Bool

    public init(topology: RuntimeTopology, selection: Binding<String?>, showProvenance: Binding<Bool>, compact: Bool = false) {
        self.topology = topology
        self._selection = selection
        self._showProvenance = showProvenance
        self.compact = compact
    }

    struct Anchor { let center: CGPoint; let radius: CGFloat }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = layout(size)
            ZStack(alignment: .topLeading) {
                GridBackdrop(spacing: 32).opacity(0.45)
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    Canvas { context, _ in
                        drawMachines(context, size: size, points: points)
                        drawLinks(context, points: points, phase: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
                ForEach(topology.machines) { machine in
                    if let anchor = points.anchors[machine.id] {
                        machineLabel(machine).position(x: anchor.center.x, y: anchor.center.y - anchor.radius - 18)
                            .onTapGesture { selection = machine.id }
                    }
                }
                if let hub = points.nodes["n:tailnet"] {
                    VStack(spacing: 3) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 13)).foregroundStyle(DaemonPalette.cyan)
                        Text("TAILSCALE").font(DaemonFont.label).tracking(1.2).foregroundStyle(DaemonPalette.cyan)
                    }
                    .position(hub)
                }
                ForEach(topology.services) { service in
                    if let point = points.nodes[service.id] {
                        serviceLabel(service).position(point)
                            .onTapGesture { selection = selection == service.id ? nil : service.id }
                    }
                }
                if showProvenance {
                    ForEach(topology.repositories, id: \.name) { repo in
                        if let point = points.nodes["r:\(repo.name)"] {
                            Text(repo.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(DaemonPalette.violet)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().stroke(DaemonPalette.violet.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                                .position(point)
                        }
                    }
                }
                header
                legend.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(12)
            }
        }
        .background(Color.black)
        .overlay(Rectangle().stroke(DaemonPalette.line))
        .clipped()
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOPOLOGÍA DE EJECUCIÓN").font(DaemonFont.label).tracking(1.6).foregroundStyle(DaemonPalette.green)
                Text("observado \(DaemonClock.relative(topology.observedAt)) · \(topology.services.count) componentes · \(topology.machines.count) máquinas")
                    .font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
            }
            Spacer()
            if !compact {
                Toggle(isOn: $showProvenance) { Text("Mostrar procedencia del código").font(DaemonFont.label) }
                    .toggleStyle(.checkbox).foregroundStyle(DaemonPalette.dim)
            }
        }
        .padding(12)
    }

    var legend: some View {
        HStack(spacing: 12) {
            ForEach([Evidence.verified, .partial, .failed, .unverified], id: \.self) { state in
                HStack(spacing: 5) { StatusDot(state, size: 6); Text(state.runtimeLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim) }
            }
            Text("· línea continua = verificada · discontinua = sin medir").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.faint)
        }
    }

    // MARK: Disposición

    struct Points {
        var anchors: [String: Anchor] = [:]
        var nodes: [String: CGPoint] = [:]
    }

    func layout(_ size: CGSize) -> Points {
        var points = Points()
        let w = size.width, h = size.height
        let unit = min(w, h)
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        // Anclas: el Desktop es el host operativo, más grande; el Mac es el observador.
        if topology.machines.contains(where: { $0.id == "m:mac" }) { points.anchors["m:mac"] = Anchor(center: at(0.17, 0.55), radius: unit * 0.17) }
        if topology.machines.contains(where: { $0.id == "m:desktop" }) { points.anchors["m:desktop"] = Anchor(center: at(0.62, 0.55), radius: unit * 0.25) }
        let phones = topology.machines.filter { $0.role == .iphone }
        for (index, phone) in phones.enumerated() { points.anchors[phone.id] = Anchor(center: at(0.38 + Double(index) * 0.08, 0.9), radius: unit * 0.05) }
        points.nodes["n:tailnet"] = at(0.38, 0.6)
        for (id, anchor) in points.anchors { points.nodes[id] = anchor.center }
        // Servicios dentro de su máquina, en anillo.
        for role in [MachineRole.mac, .desktop] {
            let id = role == .mac ? "m:mac" : "m:desktop"
            guard let anchor = points.anchors[id] else { continue }
            let list = topology.services(on: role)
            for (index, service) in list.enumerated() {
                if list.count == 1 { points.nodes[service.id] = anchor.center; continue }
                let angle = -Double.pi / 2 + Double(index) / Double(list.count) * 2 * .pi
                let r = anchor.radius * 0.55
                points.nodes[service.id] = CGPoint(x: anchor.center.x + cos(angle) * r, y: anchor.center.y + sin(angle) * r)
            }
        }
        // Internet: columna derecha; GitHub arriba.
        let externals = topology.services(on: .external)
        let column = externals.filter { $0.id != "s:github@external" }
        for (index, service) in column.enumerated() {
            points.nodes[service.id] = at(0.92, 0.32 + Double(index) * 0.3)
        }
        if externals.contains(where: { $0.id == "s:github@external" }) { points.nodes["s:github@external"] = at(0.42, 0.1) }
        // Procedencia: fila de repos bajo GitHub.
        let repos = topology.repositories
        for (index, repo) in repos.enumerated() {
            let x = 0.16 + Double(index) * (0.62 / Double(max(repos.count - 1, 1)))
            points.nodes["r:\(repo.name)"] = at(x, 0.22)
        }
        return points
    }

    // MARK: Dibujo

    func drawMachines(_ context: GraphicsContext, size: CGSize, points: Points) {
        for machine in topology.machines {
            guard let anchor = points.anchors[machine.id] else { continue }
            let rect = CGRect(x: anchor.center.x - anchor.radius, y: anchor.center.y - anchor.radius, width: anchor.radius * 2, height: anchor.radius * 2)
            let color = machine.state == .failed ? DaemonPalette.red : (machine.role == .desktop ? DaemonPalette.green : DaemonPalette.ink)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(0.07), color.opacity(0.015)]),
                                                                       center: anchor.center, startRadius: 0, endRadius: anchor.radius))
            context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        }
        // Anillo de aislamiento alrededor de los motores (solo loopback).
        for service in topology.services where service.kind == .engine {
            guard let point = points.nodes[service.id] else { continue }
            let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            context.stroke(Path(ellipseIn: rect), with: .color(service.state == .failed ? DaemonPalette.red : DaemonPalette.violet.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    func drawLinks(_ context: GraphicsContext, points: Points, phase: Double) {
        for link in topology.links where !link.provenanceOnly || showProvenance {
            guard let a = points.nodes[link.from], let b = points.nodes[link.to] else { continue }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), 1)
            let bend: CGFloat = link.provenanceOnly ? 0.08 : 0.16
            let control = CGPoint(x: mid.x - dy / length * length * bend, y: mid.y + dx / length * length * bend)
            var path = Path()
            path.move(to: a)
            path.addQuadCurve(to: b, control: control)
            let color: Color = link.provenanceOnly ? DaemonPalette.violet : (link.warning != nil ? DaemonPalette.amber : DaemonPalette.color(link.state))
            let width: CGFloat = link.provenanceOnly ? 0.8 : (link.transport == .tailscale ? 1.2 : 1.8)
            let dashed = link.state != .verified || link.provenanceOnly
            context.stroke(path, with: .color(color.opacity(link.provenanceOnly ? 0.45 : 0.85)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [4, 4] : []))
            if link.state == .verified && !link.provenanceOnly {
                let speed = link.transport == .tailscale ? 0.18 : 0.35
                let t = (phase * speed + Double(abs(link.id.hashValue % 97)) / 97).truncatingRemainder(dividingBy: 1)
                let u = 1 - t
                let p = CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x, y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
            if !compact && !link.provenanceOnly && !link.label.isEmpty && link.transport != .tailscale || link.warning != nil {
                let curveMid = CGPoint(x: 0.25 * a.x + 0.5 * control.x + 0.25 * b.x, y: 0.25 * a.y + 0.5 * control.y + 0.25 * b.y)
                let text = (link.warning != nil ? "⚠ " : "") + (link.transport == .loopback || link.transport == .observation ? link.label : "\(link.transport.label) \(link.label)")
                context.draw(Text(text).font(.system(size: 9, design: .monospaced)).foregroundColor(color), at: curveMid)
            }
        }
    }

    // MARK: Etiquetas

    func machineLabel(_ machine: RuntimeMachine) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                StatusDot(machine.state, size: 6)
                Text(machine.name.uppercased()).font(.system(size: compact ? 10 : 12, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(DaemonPalette.ink)
            }
            if !compact { Text(machine.address ?? "").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.faint) }
        }
    }

    func serviceLabel(_ service: RuntimeService) -> some View {
        let selected = selection == service.id
        return VStack(spacing: 3) {
            ZStack {
                if selected { Circle().stroke(DaemonPalette.color(service.state), lineWidth: 1).frame(width: 20, height: 20) }
                StatusDot(service.state, size: service.kind == .daemon ? 10 : 8)
                if service.warning != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(DaemonPalette.amber).offset(x: 9, y: -8)
                }
            }
            Text(service.name).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundStyle(DaemonPalette.ink).lineLimit(1)
            if !compact {
                Text(service.health).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim).lineLimit(1)
            }
        }
        .frame(width: compact ? 110 : 150)
        .contentShape(Rectangle())
    }
}

/// Inspector: runtime, red y procedencia de un componente.
public struct RuntimeInspector: View {
    let topology: RuntimeTopology
    let id: String
    public init(topology: RuntimeTopology, id: String) { self.topology = topology; self.id = id }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let service = topology.service(id) {
                HStack { Text(service.name).font(DaemonFont.heading); Spacer(); Text(service.state.runtimeLabel).font(DaemonFont.label).foregroundStyle(DaemonPalette.color(service.state)) }
                if let warning = service.warning { Text("⚠ \(warning)").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.amber) }
                SectionHeader("RUNTIME")
                KeyValueRow("Host", service.host.label)
                if let port = service.port { KeyValueRow("Puerto", ":\(port)") }
                if let bind = service.bind { KeyValueRow("Bind", bind) }
                if !service.bindEvidence.isEmpty { Text(service.bindEvidence).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint) }
                KeyValueRow("PID", service.pid.map(String.init) ?? (service.host == .desktop ? "no disponible sin SSH" : "—"))
                if let uptime = service.uptime { KeyValueRow("Activo", uptime) }
                KeyValueRow("Salud", service.health, color: DaemonPalette.color(service.state))
                if let latency = service.latencyMs { KeyValueRow("Latencia", "\(latency) ms") }
                if let check = service.lastCheck { KeyValueRow("Comprobado", DaemonClock.relative(check)) }
                SectionHeader("RED")
                KeyValueRow("Protocolo", service.protocolName)
                if let published = service.published { Text(published).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.cyan).textSelection(.enabled) }
                ForEach(topology.links.filter { !$0.provenanceOnly && ($0.from == id || $0.to == id) }) { link in
                    Text("\(link.transport.label) · \(link.label) · \(link.state.runtimeLabel)").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                }
                SectionHeader("PROCEDENCIA")
                if let source = service.source {
                    KeyValueRow("Repositorio", source.name)
                    if let local = source.localPath { Text("copia local (metadata): \(local)").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint).textSelection(.enabled) }
                    if let remote = source.remote { Text("\(remote) · \(source.remoteVerified ? "verificado con git" : "declarado")").font(DaemonFont.label).foregroundStyle(DaemonPalette.violet).textSelection(.enabled) }
                } else {
                    Text("sin procedencia verificable").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                }
                if !service.technologies.isEmpty { FlowTags(items: service.technologies) }
            } else if let machine = topology.machines.first(where: { $0.id == id }) {
                HStack { Text(machine.name).font(DaemonFont.heading); Spacer(); Text(machine.state.runtimeLabel).font(DaemonFont.label).foregroundStyle(DaemonPalette.color(machine.state)) }
                Text(machine.detail).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                if let address = machine.address { KeyValueRow("Tailscale", address) }
                SectionHeader("EN EJECUCIÓN")
                ForEach(topology.services(on: machine.role)) { service in
                    HStack(spacing: 6) { StatusDot(service.state, size: 5); Text(service.name).font(.system(size: 12)); Spacer(); Text(service.health).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).lineLimit(1) }
                }
                if topology.services(on: machine.role).isEmpty { Text("nada medido en ejecución").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint) }
            }
        }
        .instrumentPanel()
    }
}

public struct FlowTags: View {
    let items: [String]
    public init(items: [String]) { self.items = items }
    public var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item).font(DaemonFont.monoSmall).padding(.horizontal, 7).padding(.vertical, 3)
                    .foregroundStyle(DaemonPalette.green)
                    .overlay(Rectangle().stroke(DaemonPalette.green.opacity(0.35)))
            }
        }
    }
}
#endif
