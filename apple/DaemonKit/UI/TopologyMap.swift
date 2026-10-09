import Foundation
#if os(macOS)
import SwiftUI
#endif

public struct TopologyNode: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case machine, service, hub, external }
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    public let evidence: Evidence
    /// Coordenadas unitarias (0…1) y profundidad (0 frente, 1 fondo).
    public let x: Double
    public let y: Double
    public let depth: Double
    public let technologies: [String]
    public let details: [String]
}

public struct TopologyEdge: Identifiable, Sendable, Hashable {
    public let from: String
    public let to: String
    public let evidence: Evidence
    public let structural: Bool
    public var id: String { from + "→" + to }
}

/// Construye el mapa vivo a partir de una observación. Puro y testeable.
public enum TopologyLayout {
    public static func build(_ snapshot: EcosystemSnapshot, config: TopologyConfig) -> (nodes: [TopologyNode], edges: [TopologyEdge]) {
        var nodes: [TopologyNode] = []
        var edges: [TopologyEdge] = []
        let desktopPeer = snapshot.tailnet.peer(named: config.desktopHost)
        let phones = snapshot.tailnet.peers.filter { !$0.isSelf && $0.os.lowercased() == "ios" }
        let machine = snapshot.machine

        nodes.append(TopologyNode(id: "m:mac", title: "MacBook", subtitle: machine.map { "\($0.model) · carga \(String(format: "%.2f", $0.loadAverage.first ?? 0))" } ?? "este Mac",
                                  kind: .machine, evidence: .verified, x: 0.16, y: 0.5, depth: 0.2,
                                  technologies: ["macOS", "SwiftUI", "Daemon.app"], details: machine.map { ["\($0.cpuCount) núcleos", "uptime \(Int($0.uptimeSeconds / 3600)) h", "térmico \($0.thermalState)"] } ?? []))
        nodes.append(TopologyNode(id: "hub:tailnet", title: "Tailscale", subtitle: snapshot.tailnet.backendState == "Running" ? "\(snapshot.tailnet.peers.filter(\.online).count) nodos en línea" : snapshot.tailnet.backendState,
                                  kind: .hub, evidence: snapshot.tailnet.evidence, x: 0.5, y: 0.56, depth: 0.5,
                                  technologies: ["Tailscale", "WireGuard"], details: snapshot.tailnet.tailnetName.map { [$0] } ?? []))
        nodes.append(TopologyNode(id: "m:desktop", title: "Desktop", subtitle: desktopPeer.map { "\($0.shortName) · \($0.online ? "en línea" : "desconectado")" } ?? "no visto en la tailnet",
                                  kind: .machine, evidence: desktopPeer == nil ? .unverified : (desktopPeer!.online ? .verified : .failed), x: 0.8, y: 0.5, depth: 0.2,
                                  technologies: ["Windows", "OpenSSH (no verificado)"], details: desktopPeer?.ipv4.map { [$0] } ?? []))
        edges.append(TopologyEdge(from: "m:mac", to: "hub:tailnet", evidence: snapshot.tailnet.evidence, structural: true))
        edges.append(TopologyEdge(from: "hub:tailnet", to: "m:desktop", evidence: desktopPeer?.online == true ? .verified : .unverified, structural: true))
        for (index, phone) in phones.prefix(2).enumerated() {
            let id = "m:iphone\(index)"
            nodes.append(TopologyNode(id: id, title: "iPhone", subtitle: "\(phone.shortName) · \(phone.online ? "en línea" : "desconectado")", kind: .machine,
                                      evidence: phone.online ? .verified : .unverified, x: 0.5, y: 0.9 - Double(index) * 0.06, depth: 0.3,
                                      technologies: ["iOS", "Safari", "Tailscale"], details: phone.ipv4.map { [$0] } ?? []))
            edges.append(TopologyEdge(from: "hub:tailnet", to: id, evidence: phone.online ? .verified : .unverified, structural: true))
        }

        // Servicios por máquina: columnas bajo cada host.
        let macServices = snapshot.services.filter { $0.machine == .mac }
        let desktopServices = snapshot.services.filter { $0.machine == .desktop }
        func place(_ list: [ServiceStatus], x: Double) {
            for (index, status) in list.enumerated() {
                let y = 0.12 + Double(index) * (0.76 / Double(max(list.count, 1))) + 0.04
                let id = "s:\(status.id)"
                nodes.append(TopologyNode(id: id, title: status.definition.name, subtitle: status.label, kind: .service, evidence: status.evidence,
                                          x: x, y: y, depth: 0.0, technologies: status.definition.technologies,
                                          details: [status.endpoint ?? "", status.stats.p50.map { "p50 \($0) ms · p95 \(status.stats.p95 ?? $0) ms" } ?? "sin muestras",
                                                    status.listener.map { "\($0.command) PID \($0.pid) · \($0.scope.label)" } ?? ""].filter { !$0.isEmpty }))
                edges.append(TopologyEdge(from: status.machine == .mac ? "m:mac" : "m:desktop", to: id, evidence: status.evidence, structural: true))
            }
        }
        place(macServices, x: 0.31)
        place(desktopServices, x: 0.65)

        // Externos en la franja derecha.
        let externals = snapshot.services.filter { $0.machine == .external }
        for (index, status) in externals.enumerated() {
            let evidence = status.definition.id == "neon" ? (snapshot.neon?.evidence ?? .unverified) : status.evidence
            let subtitle = status.definition.id == "neon" ? (snapshot.neon.map { $0.ok == true ? "lectura correcta · \($0.durationMs) ms" : ($0.errorCode ?? "incompleto") } ?? "bajo demanda") : status.label
            nodes.append(TopologyNode(id: "s:\(status.id)", title: status.definition.name, subtitle: subtitle, kind: .external, evidence: evidence,
                                      x: 0.94, y: 0.2 + Double(index) * 0.22, depth: 0.6, technologies: status.definition.technologies,
                                      details: [status.endpoint ?? ""].filter { !$0.isEmpty }))
        }

        // Dependencias declaradas entre la instancia viva más relevante de cada servicio.
        func instance(_ id: String) -> String? {
            if let status = snapshot.best(id) { return "s:\(status.id)" }
            return nil
        }
        for status in snapshot.services where status.machine != .external {
            for dependency in status.definition.dependsOn {
                guard let target = instance(dependency) else { continue }
                // Solo dibujar la dependencia desde la instancia en uso (la mejor).
                guard snapshot.best(status.definition.id)?.id == status.id else { continue }
                let targetEvidence = nodes.first { $0.id == target }?.evidence ?? .unverified
                edges.append(TopologyEdge(from: "s:\(status.id)", to: target, evidence: Evidence.weakest([status.evidence, targetEvidence]), structural: false))
            }
        }
        return (nodes, edges)
    }
}

#if os(macOS)
public struct TopologyMapView: View {
    let snapshot: EcosystemSnapshot
    let config: TopologyConfig
    @Binding var selection: String?
    var compact: Bool

    public init(snapshot: EcosystemSnapshot, config: TopologyConfig, selection: Binding<String?>, compact: Bool = false) {
        self.snapshot = snapshot
        self.config = config
        self._selection = selection
        self.compact = compact
    }

    public var body: some View {
        let layout = TopologyLayout.build(snapshot, config: config)
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                GridBackdrop(spacing: 28).opacity(0.7)
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, _ in
                        drawPlates(context, size: size, layout: layout)
                        for edge in layout.edges {
                            guard let a = layout.nodes.first(where: { $0.id == edge.from }), let b = layout.nodes.first(where: { $0.id == edge.to }) else { continue }
                            let start = point(a, size), end = point(b, size)
                            var path = Path()
                            path.move(to: start)
                            if edge.structural {
                                path.addLine(to: end)
                            } else {
                                let mid = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 30)
                                path.addQuadCurve(to: end, control: mid)
                            }
                            let color = DaemonPalette.color(edge.evidence)
                            context.stroke(path, with: .color(color.opacity(edge.structural ? 0.22 : 0.5)),
                                           style: StrokeStyle(lineWidth: edge.structural ? 1 : 1.4, dash: edge.evidence == .verified ? [] : [3, 4]))
                            if edge.evidence == .verified && !edge.structural {
                                // Pulso que recorre los enlaces verificados.
                                let t = (phase * 0.35 + Double(abs(edge.id.hashValue % 100)) / 100).truncatingRemainder(dividingBy: 1)
                                let mid = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 30)
                                let p = quad(start, mid, end, t)
                                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(DaemonPalette.green))
                            }
                        }
                    }
                }
                ForEach(layout.nodes) { node in
                    nodeView(node)
                        .position(point(node, size))
                        .onTapGesture { selection = selection == node.id ? nil : node.id }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAPA VIVO").font(DaemonFont.label).tracking(1.6).foregroundStyle(DaemonPalette.green)
                    Text("observado \(DaemonClock.relative(snapshot.observedAt)) · \(snapshot.durationMs) ms").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                }.padding(12)
            }
        }
        .background(Color.black)
        .overlay(Rectangle().stroke(DaemonPalette.line))
        .clipped()
    }

    func point(_ node: TopologyNode, _ size: CGSize) -> CGPoint {
        // Perspectiva leve: lo profundo se acerca al centro y sube.
        let x = 0.5 + (node.x - 0.5) * (1 - node.depth * 0.08)
        let y = node.y - node.depth * 0.03
        return CGPoint(x: x * size.width, y: y * size.height)
    }

    func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    func drawPlates(_ context: GraphicsContext, size: CGSize, layout: (nodes: [TopologyNode], edges: [TopologyEdge])) {
        // Planos isométricos tenues bajo cada máquina: profundidad espacial.
        for (x, label) in [(0.235, "MACBOOK"), (0.725, "DESKTOP")] {
            let w = size.width * 0.24, h = size.height * 0.84
            let cx = x * size.width, top = size.height * 0.08
            var plate = Path()
            plate.move(to: CGPoint(x: cx - w / 2 + 18, y: top))
            plate.addLine(to: CGPoint(x: cx + w / 2 + 18, y: top))
            plate.addLine(to: CGPoint(x: cx + w / 2 - 18, y: top + h))
            plate.addLine(to: CGPoint(x: cx - w / 2 - 18, y: top + h))
            plate.closeSubpath()
            context.fill(plate, with: .color(Color.white.opacity(0.018)))
            context.stroke(plate, with: .color(DaemonPalette.line), lineWidth: 0.6)
            context.draw(Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(DaemonPalette.faint),
                         at: CGPoint(x: cx - w / 2 - 4, y: top + h + 10), anchor: .leading)
        }
    }

    @ViewBuilder func nodeView(_ node: TopologyNode) -> some View {
        let selected = selection == node.id
        let color = DaemonPalette.color(node.evidence)
        switch node.kind {
        case .machine, .hub:
            VStack(spacing: 4) {
                ZStack {
                    Rectangle().stroke(color.opacity(0.9), lineWidth: selected ? 2 : 1).frame(width: 34, height: 34).rotationEffect(.degrees(45))
                    Image(systemName: node.kind == .hub ? "point.3.connected.trianglepath.dotted" : (node.title == "iPhone" ? "iphone" : (node.title == "MacBook" ? "laptopcomputer" : "pc")))
                        .font(.system(size: 13)).foregroundStyle(DaemonPalette.ink)
                }
                Text(node.title.uppercased()).font(DaemonFont.label).tracking(1).foregroundStyle(DaemonPalette.ink)
                if !compact { Text(node.subtitle).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim).lineLimit(1) }
            }.frame(width: 150)
        case .service, .external:
            HStack(spacing: 7) {
                StatusDot(node.evidence)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title).font(.system(size: 11, weight: .medium)).foregroundStyle(DaemonPalette.ink).lineLimit(1)
                    if !compact { Text(node.subtitle).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim).lineLimit(1) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.black.opacity(0.85))
            .overlay(Rectangle().stroke(selected ? color : DaemonPalette.line, lineWidth: selected ? 1.5 : 1))
            .frame(maxWidth: 170)
        }
    }
}

/// Inspector de un nodo del mapa: estado, tecnología y procedencia.
public struct TopologyInspector: View {
    let node: TopologyNode
    public init(node: TopologyNode) { self.node = node }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(node.title).font(DaemonFont.heading); Spacer(); EvidenceTag(node.evidence) }
            Text(node.subtitle).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim).textSelection(.enabled)
            if !node.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) { ForEach(node.details, id: \.self) { Text($0).font(DaemonFont.monoSmall).textSelection(.enabled) } }
            }
            SectionHeader("TECNOLOGÍA")
            FlowTags(items: node.technologies)
        }
        .instrumentPanel()
    }
}

public struct FlowTags: View {
    let items: [String]
    public init(items: [String]) { self.items = items }
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tags }
            VStack(alignment: .leading, spacing: 6) { tags }
        }
    }
    @ViewBuilder var tags: some View {
        ForEach(items, id: \.self) { item in
            Text(item).font(DaemonFont.monoSmall).padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(DaemonPalette.green)
                .overlay(Rectangle().stroke(DaemonPalette.green.opacity(0.35)))
        }
    }
}
#endif
