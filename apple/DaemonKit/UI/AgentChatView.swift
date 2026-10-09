#if os(macOS)
import SwiftUI

/// Centro operativo: conversación con Daemon con bloques visuales vivos.
public struct AgentChatView: View {
    @ObservedObject var session: AgentSession
    let config: TopologyConfig
    let liveServicesForRepository: (String) -> Int?
    @State private var input = ""
    @FocusState private var focused: Bool

    public init(session: AgentSession, config: TopologyConfig, liveServicesForRepository: @escaping (String) -> Int?) {
        self.session = session
        self.config = config
        self.liveServicesForRepository = liveServicesForRepository
    }

    static let suggestions = ["¿Cómo está choisys?", "¿Qué repos tienen cambios?", "¿Qué proceso usa 8081?", "¿Está vivo el Cubo del Desktop?",
                              "Comprueba la tailnet", "¿Qué ha cambiado hoy?", "¿Qué PRs están abiertas?", "Ejecuta los tests de daemon-core",
                              "Muéstrame el cubo de daemon-core", "¿Cómo va el Mac?"]

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DaemonPalette.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if session.messages.isEmpty { welcome }
                        ForEach(session.messages) { message in
                            MessageRow(message: message, perform: { session.perform($0) }, config: config, liveServices: liveServicesForRepository).id(message.id)
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 22)
                }
                .onChange(of: session.messages.count) { _, _ in
                    if let last = session.messages.last?.id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) } }
                }
                .onChange(of: session.busy) { _, _ in if let last = session.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
            }
            Rectangle().fill(DaemonPalette.line).frame(height: 1)
            composer
        }
        .background(Color.black)
    }

    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            DaemonSigil(active: session.busy).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("DAEMON").font(.system(size: 15, weight: .light, design: .monospaced)).tracking(4)
                Text(DaemonPersona.tagline).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
            }
            Spacer()
            Text(session.llmEnabled ? "MOTOR · LOCAL + \(AgentSettings.model.uppercased())" : "MOTOR · LOCAL · 0 TOKENS")
                .font(DaemonFont.label).tracking(1).foregroundStyle(DaemonPalette.dim)
            Button { session.clear() } label: { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(DaemonPalette.dim).help("Vaciar conversación")
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(SpeedLines(active: session.busy))
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialLabel("02", "Agente")
            RisoTitle("Mido antes de opinar.", size: 34)
            Text(DaemonPersona.identity).font(.system(size: 13)).foregroundStyle(DaemonPalette.dim).frame(maxWidth: 620, alignment: .leading)
            Text("Cada respuesta lleva su evidencia: verificado, parcial o no verificado. Las acciones con riesgo piden tu pulsación.")
                .font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.faint)
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { session.send(suggestion) }
                        .buttonStyle(.plain).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6).overlay(Rectangle().stroke(DaemonPalette.line))
                }
            }
        }.padding(.top, 30)
    }

    var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("›").font(.system(size: 18, weight: .light, design: .monospaced)).foregroundStyle(DaemonPalette.green).padding(.bottom, 2)
            TextField("Pregunta a Daemon por repos, puertos, red, choisys, Neon o el Cubo…", text: $input, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).lineLimit(1...5)
                .focused($focused).onSubmit(send)
            Button(action: send) {
                Text(session.busy ? "MIDIENDO" : "ENVIAR").font(DaemonFont.label).tracking(1.2)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(Color.black).background(session.busy ? DaemonPalette.dim : DaemonPalette.green)
            }
            .buttonStyle(.plain).disabled(session.busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .onAppear { focused = true }
    }

    func send() {
        let text = input
        input = ""
        SoundBoard.shared.play(.send)
        session.send(text)
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let perform: (AgentAction) -> Void
    let config: TopologyConfig
    let liveServices: (String) -> Int?

    var roleLabel: String { message.role == .clod ? "CLOD" : "DAEMON" }
    var roleColor: Color { message.role == .clod ? DaemonPalette.violet : DaemonPalette.green }

    var body: some View {
        if message.role == .neo {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("NEO").font(DaemonFont.label).tracking(1.2).foregroundStyle(DaemonPalette.dim).frame(width: 52, alignment: .leading)
                Text(message.text).font(.system(size: 14)).foregroundStyle(DaemonPalette.ink).textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(roleLabel).font(DaemonFont.label).tracking(1.2).foregroundStyle(roleColor)
                    if let evidence = message.evidence { StatusDot(evidence) }
                }.frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    if message.pending {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("midiendo el entorno…").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim) }
                    } else {
                        Text(message.text).font(.system(size: 14)).foregroundStyle(DaemonPalette.ink).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        ForEach(message.blocks) { block in BlockView(block: block, perform: perform, config: config, liveServices: liveServices) }
                        HStack(spacing: 10) {
                            if let evidence = message.evidence { EvidenceTag(evidence) }
                            if !message.tools.isEmpty { Text(message.tools.joined(separator: " · ")).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint) }
                            Text(DaemonClock.iso(message.timestamp)).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Renderiza cada bloque vivo de una respuesta.
struct BlockView: View {
    let block: AgentBlock
    let perform: (AgentAction) -> Void
    let config: TopologyConfig
    let liveServices: (String) -> Int?
    @State private var topologySelection: String?

    var body: some View {
        switch block {
        case .metrics(let metrics):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) { ForEach(metrics) { Readout($0) } }
        case .services(let services):
            ServiceTable(services: services)
        case .path(let hops):
            PathChain(hops: hops)
        case .ports(let sockets):
            PortTable(sockets: sockets, declared: config.services)
        case .tailnet(let snapshot):
            TailnetTable(snapshot: snapshot)
        case .commits(let commits, let title):
            CommitTimeline(commits: commits, title: title)
        case .changes(let changes):
            VStack(alignment: .leading, spacing: 3) {
                SectionHeader("CAMBIOS", trailing: "\(changes.count) archivos")
                ForEach(changes.prefix(25)) { change in
                    HStack {
                        Text(change.path).font(DaemonFont.monoSmall).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("+\(change.added.map(String.init) ?? "bin")").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.green)
                        Text("−\(change.removed.map(String.init) ?? "bin")").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.red)
                    }
                }
            }
        case .pullRequests(let prs, let slug):
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader("PULL REQUESTS", slug)
                ForEach(prs) { pr in
                    HStack(spacing: 10) {
                        Text("#\(pr.number)").font(DaemonFont.mono).foregroundStyle(pr.state == "OPEN" ? DaemonPalette.green : DaemonPalette.dim).frame(width: 46, alignment: .leading)
                        Text(pr.title).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text(pr.isDraft == true ? "DRAFT" : pr.state).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                        if let url = URL(string: pr.url) { Link(destination: url) { Image(systemName: "arrow.up.right.square") }.foregroundStyle(DaemonPalette.dim) }
                    }
                }
            }
        case .runs(let runs):
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader("GITHUB ACTIONS")
                ForEach(runs) { run in
                    HStack(spacing: 10) {
                        StatusDot(run.conclusion == "success" ? .verified : (run.conclusion == "failure" ? .failed : .partial))
                        Text(run.name ?? "workflow").font(.system(size: 12))
                        Text(run.headBranch ?? "").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                        Spacer()
                        Text(run.conclusion ?? run.status).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                    }
                }
            }
        case .code(let title, let text):
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("SALIDA", title)
                ScrollView(.horizontal) {
                    Text(text).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.ink).textSelection(.enabled).padding(12)
                }
                .background(DaemonPalette.panel).overlay(Rectangle().stroke(DaemonPalette.line)).frame(maxHeight: 260)
            }
        case .alerts(let alerts):
            AlertList(alerts: alerts)
        case .cube(let repository, let record):
            MetricCubePanel(runs: [CubeModel.run(record: record, repository: repository, liveServices: liveServices(repository.name))], height: 340)
        case .topology(let snapshot):
            TopologyMapView(snapshot: snapshot, config: config, selection: $topologySelection, compact: false).frame(height: 360)
        case .tools(let tools):
            TechnologyTable(tools: tools)
        case .provenance(let provenance, let evidence):
            HStack(spacing: 8) {
                EvidenceTag(evidence)
                Text("\(provenance.source) · \(provenance.method) · \(DaemonClock.iso(provenance.observedAt))").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
            }
        case .actions(let actions):
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    ActionButton(action: action) { perform(action) }
                }
            }
        }
    }
}

public struct ActionButton: View {
    let action: AgentAction
    let perform: () -> Void
    public init(action: AgentAction, perform: @escaping () -> Void) { self.action = action; self.perform = perform }
    @State private var confirming = false

    public var body: some View {
        Button {
            if action.needsConfirmation || action.risk == .destructive { confirming = true } else { perform() }
        } label: {
            HStack(spacing: 6) {
                Text(action.risk.rawValue).font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(action.risk == .read ? DaemonPalette.faint : (action.risk == .destructive ? DaemonPalette.red : DaemonPalette.amber))
                    .foregroundStyle(Color.black)
                Text(action.title).font(.system(size: 12))
            }
            .padding(.horizontal, 10).padding(.vertical, 6).overlay(Rectangle().stroke(DaemonPalette.line))
        }
        .buttonStyle(.plain)
        .confirmationDialog("¿Ejecutar «\(action.title)»?", isPresented: $confirming) {
            Button("Ejecutar", role: action.risk == .destructive ? .destructive : nil, action: perform)
        } message: {
            Text("Herramienta \(action.tool) · nivel \(action.risk.label). Daemon registra qué hace y cómo deshacerlo.")
        }
    }
}

public struct ServiceTable: View {
    let services: [ServiceStatus]
    public init(services: [ServiceStatus]) { self.services = services }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("SERVICIOS", trailing: "p50 · p95")
            ForEach(services) { status in
                HStack(spacing: 10) {
                    StatusDot(status.evidence)
                    Text(status.definition.name).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                    Text(status.machine.label).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).frame(width: 96, alignment: .leading)
                    Text(status.label).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.color(status.evidence)).lineLimit(1)
                    Spacer()
                    Text(status.stats.p50.map { "\($0) · \(status.stats.p95 ?? $0) ms" } ?? "—").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                }
                .padding(.vertical, 6)
                .help("\(status.endpoint ?? "sin endpoint")\n\(status.probe.map { "\($0.provenance.method) · \(DaemonClock.iso($0.provenance.observedAt))" } ?? "sin sonda")\nTecnología: \(status.definition.technologies.joined(separator: ", "))")
                Rectangle().fill(DaemonPalette.grid).frame(height: 1)
            }
        }
    }
}

public struct PathChain: View {
    let hops: [PathHop]
    public init(hops: [PathHop]) { self.hops = hops }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("RUTA DEL PRODUCTO", "cliente → frontend → API → DB → Cubo")
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 0) {
                            StatusDot(hop.evidence, size: 10)
                            if index < hops.count - 1 {
                                Rectangle().fill(DaemonPalette.color(hop.evidence).opacity(0.5)).frame(height: 1)
                            }
                        }
                        Text(hop.name).font(.system(size: 11, weight: .medium)).lineLimit(2)
                        Text(hop.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(DaemonPalette.color(hop.evidence)).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

public struct PortTable: View {
    let sockets: [ListeningSocket]
    let declared: [ServiceDefinition]
    public init(sockets: [ListeningSocket], declared: [ServiceDefinition]) { self.sockets = sockets; self.declared = declared }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("PUERTOS", trailing: "\(sockets.count) listeners")
            HStack {
                ForEach(["PUERTO", "PROCESO", "PID", "INTERFAZ", "CPU", "MEM", "ACTIVO", "SERVICIO"], id: \.self) { title in
                    Text(title).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.vertical, 5)
            ForEach(sockets) { socket in
                let service = declared.first { $0.port == socket.port }
                let warn = (socket.scope >= .allInterfaces && (service != nil || socket.isDevelopmentProcess)) || (service?.loopbackOnly == true && socket.scope != .loopback)
                HStack {
                    Text(":\(socket.port)").foregroundStyle(service == nil ? DaemonPalette.ink : DaemonPalette.green)
                    Text(socket.command).lineLimit(1)
                    Text("\(socket.pid)").foregroundStyle(DaemonPalette.dim)
                    Text("\(socket.address) · \(socket.scope.label)").foregroundStyle(warn ? DaemonPalette.amber : DaemonPalette.dim).lineLimit(1)
                    Text(socket.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                    Text(socket.residentBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—")
                    Text(socket.elapsed ?? "—").foregroundStyle(DaemonPalette.dim)
                    Text(service?.name ?? socket.knownLabel ?? "—").foregroundStyle(service == nil ? DaemonPalette.faint : DaemonPalette.dim).lineLimit(1)
                }
                .font(DaemonFont.monoSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                Rectangle().fill(DaemonPalette.grid).frame(height: 1)
            }
        }
    }
}

public struct TailnetTable: View {
    let snapshot: TailnetSnapshot
    public init(snapshot: TailnetSnapshot) { self.snapshot = snapshot }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("TAILNET", snapshot.tailnetName, trailing: snapshot.backendState)
            ForEach(snapshot.peers) { peer in
                HStack(spacing: 10) {
                    StatusDot(peer.online ? .verified : .unverified)
                    Text(peer.shortName + (peer.isSelf ? " (este Mac)" : "")).font(.system(size: 12)).frame(width: 200, alignment: .leading)
                    Text(peer.os).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).frame(width: 70, alignment: .leading)
                    Text(peer.ipv4 ?? "—").font(DaemonFont.monoSmall)
                    Spacer()
                    Text(peer.online ? "en línea" : (peer.lastSeen.map { "visto \(DaemonClock.relative($0))" } ?? "desconectado")).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                }
                .padding(.vertical, 5)
                Rectangle().fill(DaemonPalette.grid).frame(height: 1)
            }
        }
    }
}

public struct CommitTimeline: View {
    let commits: [CommitEvent]
    let title: String
    public init(commits: [CommitEvent], title: String) { self.commits = commits; self.title = title }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("TIMELINE", title, trailing: "\(commits.count) commits")
            ForEach(commits) { commit in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().stroke(DaemonPalette.green, lineWidth: 1).frame(width: 7, height: 7)
                        Rectangle().fill(DaemonPalette.line).frame(width: 1).frame(maxHeight: .infinity)
                    }.frame(width: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject).font(.system(size: 12)).lineLimit(2)
                        Text("\(commit.shortHash) · \(commit.author) · \(DaemonClock.relative(commit.timestamp))").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                    }.padding(.bottom, 8)
                }
            }
        }
    }
}

public struct AlertList: View {
    let alerts: [DaemonAlert]
    public init(alerts: [DaemonAlert]) { self.alerts = alerts }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(DaemonPalette.color(alert.level)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(alert.level == .critical ? "ALERTA CRÍTICA" : alert.level.rawValue.uppercased()) · \(alert.title)").font(DaemonFont.label).tracking(0.8).foregroundStyle(DaemonPalette.color(alert.level))
                        Text(alert.detail).font(.system(size: 12)).foregroundStyle(DaemonPalette.ink)
                        Text("\(alert.provenance.source) · \(alert.provenance.method)").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.faint)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(10).background(DaemonPalette.color(alert.level).opacity(0.06))
            }
        }
    }
}

/// Sigilo de Daemon: cubo alámbrico que gira mientras mide.
public struct DaemonSigil: View {
    let active: Bool
    public init(active: Bool) { self.active = active }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
            let angle = active ? timeline.date.timeIntervalSinceReferenceDate * 1.4 : 0.6
            Canvas { context, size in
                let s = min(size.width, size.height) * 0.32
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let corners: [(Double, Double, Double)] = [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
                let projected = corners.map { c -> CGPoint in
                    let x = c.0 * cos(angle) - c.2 * sin(angle)
                    let z = c.0 * sin(angle) + c.2 * cos(angle)
                    let y = c.1 * cos(0.5) - z * sin(0.5)
                    return CGPoint(x: center.x + x * s, y: center.y + y * s)
                }
                var path = Path()
                for (a, b) in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)] {
                    path.move(to: projected[a]); path.addLine(to: projected[b])
                }
                context.stroke(path, with: .color(DaemonPalette.green), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(DaemonPalette.green))
            }
        }
    }
}

/// Distribución en filas que se parten (para chips).
public struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    public init(spacing: CGFloat = 8) { self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}
#endif
