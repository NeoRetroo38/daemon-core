#if os(macOS)
import SwiftUI

/// Mapa vivo: máquinas como nodos circulares, servicios como tarjetas y
/// enlaces con protocolo y latencia. El estilo de la línea dice cuánto sabemos:
/// continua = verificada, discontinua = detectada, punteada = no medida.
/// Nunca se anima un enlace que no se haya medido.
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

    static let github = "s:github@external", internet = "n:internet", tailnet = "n:tailnet"

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = layout(size)
            ZStack(alignment: .topLeading) {
                GridBackdrop(spacing: 32).opacity(0.45)
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    Canvas { context, _ in
                        drawLinks(context, points: points, phase: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
                hub(Self.internet, "Internet", "globe", points)
                hub(Self.tailnet, "Tailscale", "point.3.connected.trianglepath.dotted", points)
                ForEach(topology.machines) { machine in
                    if let point = points[machine.id] { machineNode(machine, at: point, unit: min(size.width, size.height)) }
                }
                // Lo que corre en el Mac va dentro de su tarjeta; aquí solo el Desktop y lo externo.
                ForEach(topology.services.filter { $0.host != .mac }) { service in
                    if let point = points[service.id] {
                        serviceCard(service).position(point)
                            .onTapGesture { selection = selection == service.id ? nil : service.id }
                    }
                }
                if showProvenance {
                    HStack(spacing: 8) {
                        ForEach(topology.repositories, id: \.name) { repo in
                            Text(repo.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(DaemonPalette.violet)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().stroke(DaemonPalette.violet.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                        }
                    }
                    .position(x: size.width / 2, y: size.height - 64)
                }
                header
                if let notice = topology.notice, !compact {
                    Text("⚠ \(notice)").font(.system(size: 11)).foregroundStyle(DaemonPalette.amber)
                        .padding(8).background(DaemonPalette.amber.opacity(0.08)).overlay(Rectangle().stroke(DaemonPalette.amber.opacity(0.4)))
                        .frame(maxWidth: size.width * 0.7, alignment: .leading).position(x: size.width / 2, y: size.height - 64)
                }
                legend.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(12)
            }
        }
        .background(Color.black)
        .overlay(Rectangle().stroke(DaemonPalette.line))
        .clipped()
    }

    var header: some View {
        HStack(alignment: .top) {
            Text("observado \(DaemonClock.relative(topology.observedAt)) · \(topology.services.count) componentes · \(topology.machines.count) máquinas")
                .font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
            Spacer()
            if !compact {
                Toggle(isOn: $showProvenance) { Text("Mostrar procedencia del código").font(DaemonFont.label) }
                    .toggleStyle(.checkbox).foregroundStyle(DaemonPalette.dim)
            }
        }
        .padding(12)
    }

    var legend: some View {
        HStack(spacing: 14) {
            ForEach([Evidence.verified, .partial, .failed, .unverified], id: \.self) { state in
                HStack(spacing: 5) { StatusDot(state, size: 6); Text(state.runtimeLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim) }
            }
            ForEach([(Evidence.verified, "Conexión verificada"), (.partial, "Conexión detectada"), (.unverified, "Conexión no medida")], id: \.1) { item in
                HStack(spacing: 5) {
                    Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 26, y: 0)) }
                        .stroke(DaemonPalette.green, style: StrokeStyle(lineWidth: 1.4, dash: Self.dash(item.0)))
                        .frame(width: 26, height: 1)
                    Text(item.1).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.black.opacity(0.85)).overlay(Rectangle().stroke(DaemonPalette.line))
    }

    static func dash(_ state: Evidence) -> [CGFloat] {
        switch state {
        case .verified, .failed: []
        case .partial: [6, 4]
        case .unverified: [1.5, 4]
        }
    }

    // MARK: Disposición (fracciones del lienzo, como la maqueta de Neo)

    func layout(_ size: CGSize) -> [String: CGPoint] {
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
        var points: [String: CGPoint] = [Self.github: at(0.5, 0.15), Self.internet: at(0.5, 0.36), Self.tailnet: at(0.5, 0.58)]
        for machine in topology.machines {
            switch machine.role {
            case .mac: points[machine.id] = at(0.2, 0.46)
            case .desktop: points[machine.id] = at(0.7, 0.44)
            default:
                let phones = topology.machines.filter { $0.role == .iphone }
                let index = phones.firstIndex(of: machine) ?? 0
                points[machine.id] = at(0.4 - Double(index) * 0.12, 0.72)
            }
        }
        for service in topology.services(on: .mac) { points[service.id] = points["m:mac"] }
        // Columna derecha: lo que sirve el Desktop y sus dependencias externas.
        let column = topology.services.filter { ($0.host == .desktop && $0.kind != .engine) || ($0.host == .external && $0.id != Self.github) }
        for (index, service) in column.enumerated() {
            points[service.id] = at(0.86, 0.2 + Double(index) * (0.6 / Double(max(column.count - 1, 1))))
        }
        // El Cubo, bajo el Desktop: solo loopback.
        for engine in topology.services where engine.kind == .engine && engine.host == .desktop {
            points[engine.id] = at(0.62, 0.8)
        }
        return points
    }

    /// Enlaces estructurales que la maqueta dibuja y la topología no mide: siempre «no medida».
    var structuralLinks: [RuntimeLink] {
        var links: [RuntimeLink] = []
        let github = topology.service(Self.github)
        links.append(RuntimeLink(from: Self.github, to: Self.internet, transport: .https,
                                 label: github?.latencyMs.map { "\($0) ms" } ?? "", state: github?.state ?? .unverified, warning: nil, provenanceOnly: false))
        for machine in topology.machines where machine.role != .iphone {
            links.append(RuntimeLink(from: machine.id, to: Self.internet, transport: .https, label: "", state: .unverified, warning: nil, provenanceOnly: false))
        }
        for service in topology.services(on: .desktop) where service.kind == .service {
            links.append(RuntimeLink(from: "m:desktop", to: service.id, transport: .https,
                                     label: service.latencyMs.map { "\($0) ms" } ?? "", state: service.state, warning: nil, provenanceOnly: false))
        }
        return links
    }

    // MARK: Dibujo

    func drawLinks(_ context: GraphicsContext, points: [String: CGPoint], phase: Double) {
        for link in structuralLinks + topology.links where !link.provenanceOnly || showProvenance {
            guard let a = points[link.from], let b = points[link.to], a != b else { continue }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let control = CGPoint(x: mid.x - (b.y - a.y) * 0.08, y: mid.y + (b.x - a.x) * 0.08)
            var path = Path()
            path.move(to: a)
            path.addQuadCurve(to: b, control: control)
            let color: Color = link.warning != nil ? DaemonPalette.amber : (link.state == .failed ? DaemonPalette.red : DaemonPalette.green)
            let glow = link.state == .verified ? 0.95 : 0.55
            if link.state == .verified {
                context.stroke(path, with: .color(color.opacity(0.18)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            context.stroke(path, with: .color(color.opacity(glow)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: Self.dash(link.state)))
            if link.state == .verified {
                let speed = link.transport == .tailscale ? 0.18 : 0.35
                let t = (phase * speed + Double(abs(link.id.hashValue % 97)) / 97).truncatingRemainder(dividingBy: 1)
                let u = 1 - t
                let p = CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x, y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
            guard !compact || link.warning != nil else { continue }
            let title = (link.warning != nil ? "⚠ " : "") + (link.transport == .observation ? "sonda" : link.transport.label)
            let resolved = context.resolve(Text(title + (link.label.isEmpty ? "" : "\n" + link.label))
                .font(.system(size: 10, design: .monospaced)).foregroundColor(color))
            let curveMid = CGPoint(x: 0.25 * a.x + 0.5 * control.x + 0.25 * b.x, y: 0.25 * a.y + 0.5 * control.y + 0.25 * b.y)
            let box = resolved.measure(in: CGSize(width: 220, height: 60))
            context.fill(Path(CGRect(x: curveMid.x - box.width / 2 - 4, y: curveMid.y - box.height / 2 - 2, width: box.width + 8, height: box.height + 4)),
                         with: .color(Color.black.opacity(0.85)))
            context.draw(resolved, at: curveMid)
        }
    }

    // MARK: Nodos

    func hub(_ id: String, _ name: String, _ icon: String, _ points: [String: CGPoint]) -> some View {
        Group {
            if let point = points[id] {
                Card(icon: icon, title: name, state: nil, lines: [], bullets: [], compact: compact).position(point)
            }
        }
    }

    func machineNode(_ machine: RuntimeMachine, at point: CGPoint, unit: CGFloat) -> some View {
        let radius = unit * (machine.role == .iphone ? 0.045 : 0.065)
        let icon = machine.role == .mac ? "laptopcomputer" : (machine.role == .desktop ? "desktopcomputer" : "iphone")
        let bullets = topology.services(on: machine.role).filter { $0.kind != .engine }.map(\.name)
            + topology.services.filter { $0.kind == .engine && $0.host == machine.role }.map(\.name)
        return ZStack {
            Circle().fill(DaemonPalette.green.opacity(0.06)).frame(width: radius * 2, height: radius * 2)
            Circle().stroke(DaemonPalette.color(machine.state).opacity(0.85), lineWidth: 1.4).frame(width: radius * 2, height: radius * 2)
                .shadow(color: DaemonPalette.green.opacity(machine.state == .verified ? 0.5 : 0), radius: 10)
            Circle().stroke(DaemonPalette.green.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                .frame(width: radius * 2.6, height: radius * 2.6)
            Image(systemName: icon).font(.system(size: radius * 0.6)).foregroundStyle(DaemonPalette.ink)
            Card(icon: nil, title: machine.name, state: machine.state, lines: [machine.address].compactMap { $0 }, bullets: bullets, compact: compact)
                .offset(y: radius + 54)
        }
        .position(point)
        .onTapGesture { selection = machine.id }
    }

    func serviceCard(_ service: RuntimeService) -> some View {
        let icon: String
        switch service.kind {
        case .engine: icon = "cube.transparent"
        case .external: icon = service.id.contains("neon") ? "cylinder.split.1x2" : (service.id == Self.github ? "chevron.left.forwardslash.chevron.right" : "globe")
        default: icon = service.id.contains("choisys") ? "cube" : "circle.hexagongrid"
        }
        var lines = [service.health]
        if service.kind == .engine { lines.append(service.bind.map { "\($0):\(service.port.map(String.init) ?? "")" } ?? "") }
        else if let latency = service.latencyMs { lines.append("\(latency) ms" + (service.port.map { " · :\($0)" } ?? "")) }
        return Card(icon: icon, title: service.name, state: service.state, lines: lines.filter { !$0.isEmpty }, bullets: [],
                    compact: compact, selected: selection == service.id, warning: service.warning, accent: service.kind == .engine)
    }
}

/// Tarjeta de nodo: icono, nombre, estado y detalle medido. Líneas finas, sin sombras de SaaS.
struct Card: View {
    let icon: String?
    let title: String
    let state: Evidence?
    let lines: [String]
    let bullets: [String]
    let compact: Bool
    var selected = false
    var warning: String? = nil
    var accent = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(accent ? DaemonPalette.green : DaemonPalette.ink).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // La tarjeta usa su tamaño ideal (fixedSize): se recorta aquí para que no salga del lienzo.
                    Text(title.count > 26 ? title.prefix(25) + "…" : title)
                        .font(.system(size: compact ? 11 : 12.5, weight: .semibold)).foregroundStyle(DaemonPalette.ink).lineLimit(1)
                    if warning != nil { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(DaemonPalette.amber) }
                }
                if let state {
                    HStack(spacing: 4) {
                        StatusDot(state, size: 6)
                        Text(state == .verified ? "OK" : state.runtimeLabel).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(DaemonPalette.color(state))
                    }
                }
                if !compact {
                    ForEach(lines, id: \.self) { Text($0).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(DaemonPalette.dim).lineLimit(1) }
                    ForEach(bullets, id: \.self) { Text("• " + $0).font(.system(size: 10)).foregroundStyle(DaemonPalette.dim).lineLimit(1) }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.black.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke((selected || accent ? DaemonPalette.green : DaemonPalette.ink).opacity(selected ? 0.9 : 0.35), lineWidth: 1))
        .fixedSize()
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
