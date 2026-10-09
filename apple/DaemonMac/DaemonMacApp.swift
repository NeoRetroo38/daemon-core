import AppKit
import DaemonKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum Section: String, CaseIterable, Identifiable {
    case map, agent, repositories, system, network, technology
    var id: String { rawValue }
    var code: String {
        switch self { case .map: "01"; case .agent: "02"; case .repositories: "03"; case .system: "04"; case .network: "05"; case .technology: "06" }
    }
    var title: String {
        switch self { case .map: "Mapa vivo"; case .agent: "Agente"; case .repositories: "Repositorios"; case .system: "Sistema"; case .network: "Red"; case .technology: "Tecnología" }
    }
    var symbol: String {
        switch self {
        case .map: "point.3.filled.connected.trianglepath.dotted"; case .agent: "text.bubble"; case .repositories: "shippingbox"
        case .system: "cpu"; case .network: "network"; case .technology: "square.stack.3d.up"
        }
    }
}

@MainActor
final class DaemonAppModel: ObservableObject {
    @Published private(set) var repositoryPaths: [String]
    @Published private(set) var snapshot: DaemonSnapshot?
    @Published private(set) var ecosystem: EcosystemSnapshot?
    @Published private(set) var toolchain: ToolchainSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var refreshing = false
    @Published private(set) var observing = false
    @Published var selectedRepositoryPath: String?
    let config = TopologyConfig.load()
    private(set) var session: AgentSession!
    private static let catalogKey = "daemon.repositoryCatalog.v1"
    private var loop: Task<Void, Never>?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--repo"), arguments.indices.contains(index + 1) {
            repositoryPaths = [arguments[index + 1]]
        } else {
            repositoryPaths = UserDefaults.standard.stringArray(forKey: Self.catalogKey) ?? []
        }
        session = AgentSession { [unowned self] in
            AgentContext(repositories: self.snapshot?.repositories ?? [], ecosystem: self.ecosystem, config: self.config,
                         selectedRepositoryPath: self.selectedRepositoryPath)
        }
        if repositoryPaths.isEmpty { discover() }
    }

    var repositories: [RepositorySnapshot] { snapshot?.repositories ?? [] }

    func liveServices(for repository: String) -> Int? {
        guard let ecosystem else { return nil }
        return ecosystem.services.filter { $0.definition.repository == repository && $0.alive }.count
    }

    func discover() {
        let found = RepositoryDiscovery.discover(root: config.workspaceRoot).filter { !$0.worktree }
        for repository in found where !repositoryPaths.contains(repository.path) { repositoryPaths.append(repository.path) }
        persist()
    }

    func addRepository(_ raw: String) {
        let path = (raw as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !repositoryPaths.contains(path) else { return }
        repositoryPaths.append(path)
        persist()
    }

    func removeRepository(_ path: String) {
        repositoryPaths.removeAll { $0 == path }
        if selectedRepositoryPath == path { selectedRepositoryPath = nil }
        persist()
    }

    private func persist() { UserDefaults.standard.set(repositoryPaths, forKey: Self.catalogKey) }

    func refreshRepositories() async {
        guard !refreshing else { return }
        guard !repositoryPaths.isEmpty else { snapshot = nil; error = "Añade al catálogo uno o más repositorios Git."; return }
        refreshing = true
        error = nil
        let paths = repositoryPaths
        do {
            snapshot = try await Task.detached(priority: .userInitiated) { try CoreBridge.snapshot(repositoryPaths: paths) }.value
            if let repositories = snapshot?.repositories {
                Task.detached(priority: .utility) {
                    for repository in repositories where repository.evidence == .verified { _ = await RepositoryIndex.shared.record(for: repository) }
                    _ = await RepositoryIndex.shared.digest(for: repositories)
                }
            }
        } catch {
            snapshot = nil
            self.error = error.localizedDescription
        }
        refreshing = false
    }

    func refreshEcosystem() async {
        guard !observing else { return }
        observing = true
        ecosystem = await EcosystemProbe.observe(config: config)
        observing = false
    }

    func refreshToolchain() async { toolchain = await ToolchainProbe.observe() }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.refreshRepositories()
            await self?.refreshEcosystem()
            await self?.refreshToolchain()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, NSApp.isActive else { continue }
                await self.refreshEcosystem()
            }
        }
    }
}

@main
struct DaemonMacApp: App {
    @StateObject private var model = DaemonAppModel()

    var body: some Scene {
        WindowGroup("Daemon") {
            DaemonRoot(model: model, session: model.session)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1380, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Actualizar todo") { Task { await model.refreshRepositories(); await model.refreshEcosystem() } }.keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct DaemonRoot: View {
    @ObservedObject var model: DaemonAppModel
    @ObservedObject var session: AgentSession
    @State private var section: Section = .map
    @State private var mapSelection: String?
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(DaemonPalette.line).frame(width: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .task { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .daemonShowAgent)) { _ in section = .agent }
        .sheet(isPresented: $showingSettings) { SettingsSheet(config: model.config) }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DaemonSigil(active: session.busy || model.observing).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DAEMON").font(.system(size: 17, weight: .light, design: .monospaced)).tracking(4)
                    Text("control plane · Scenarys").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                }
            }.padding(.top, 34).padding(.bottom, 26)
            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 10) {
                        Text(item.code).font(DaemonFont.label).foregroundStyle(section == item ? DaemonPalette.green : DaemonPalette.faint)
                        Image(systemName: item.symbol).font(.system(size: 11)).frame(width: 16)
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                        if item == .map, let alerts = model.ecosystem?.alerts.filter({ $0.level == .critical }), !alerts.isEmpty {
                            Text("\(alerts.count)").font(DaemonFont.label).padding(.horizontal, 5).background(DaemonPalette.red).foregroundStyle(Color.black)
                        }
                    }
                    .foregroundStyle(section == item ? DaemonPalette.ink : DaemonPalette.dim)
                    .padding(.vertical, 7).padding(.horizontal, 8)
                    .background(section == item ? Color.white.opacity(0.05) : Color.clear)
                    .overlay(alignment: .leading) { Rectangle().fill(section == item ? DaemonPalette.green : .clear).frame(width: 2) }
                }.buttonStyle(.plain)
            }
            SectionHeader("REPOS").padding(.top, 24).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.repositories) { repository in
                        Button {
                            model.selectedRepositoryPath = repository.path
                            section = .repositories
                        } label: {
                            HStack(spacing: 7) {
                                StatusDot(repository.evidence != .verified ? .unverified : (repository.dirty == true ? .partial : .verified), size: 5)
                                Text(repository.name).font(DaemonFont.monoSmall).lineLimit(1)
                                Spacer()
                                if let behind = repository.behind, behind > 0 { Text("−\(behind)").font(DaemonFont.label).foregroundStyle(DaemonPalette.amber) }
                            }
                            .foregroundStyle(model.selectedRepositoryPath == repository.path && section == .repositories ? DaemonPalette.green : DaemonPalette.ink)
                            .padding(.vertical, 3)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 4) {
                if let ecosystem = model.ecosystem {
                    Text("observado \(DaemonClock.relative(ecosystem.observedAt))").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                }
                Text("CORE \(CoreBridge.version) · \(session.llmEnabled ? "LLM opcional activo" : "agente local")").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                Button { showingSettings = true } label: { Label("Ajustes", systemImage: "slider.horizontal.3").font(DaemonFont.label) }
                    .buttonStyle(.plain).foregroundStyle(DaemonPalette.dim).padding(.top, 4)
            }.padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .frame(width: 222)
        .background(DaemonPalette.panel.opacity(0.6))
    }

    @ViewBuilder var content: some View {
        switch section {
        case .agent:
            AgentChatView(session: session, config: model.config) { model.liveServices(for: $0) }
        case .map:
            ScrollView { OverviewView(model: model, session: session, selection: $mapSelection).padding(28) }
        case .repositories:
            ScrollView { RepositoriesView(model: model, session: session).padding(28) }
        case .system:
            ScrollView { SystemView(model: model).padding(28) }
        case .network:
            ScrollView { NetworkView(model: model, session: session) { section = .agent }.padding(28) }
        case .technology:
            ScrollView { TechnologyScreen(model: model).padding(28) }
        }
    }
}

struct ScreenTitle: View {
    let code: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(code).font(DaemonFont.label).tracking(2).foregroundStyle(DaemonPalette.green)
            Text(title).font(DaemonFont.title)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(DaemonPalette.dim)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewView: View {
    @ObservedObject var model: DaemonAppModel
    let session: AgentSession
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                ScreenTitle(code: "01 · MAPA VIVO", title: "Ecosistema Scenarys", subtitle: "Máquinas, servicios, red y dependencias con su evidencia. Daemon observa; Neo decide.")
                Button(model.observing ? "MIDIENDO…" : "MEDIR AHORA") { Task { await model.refreshEcosystem() } }
                    .buttonStyle(.plain).font(DaemonFont.label).tracking(1).foregroundStyle(DaemonPalette.green).disabled(model.observing)
            }
            if let ecosystem = model.ecosystem {
                HStack(alignment: .top, spacing: 14) {
                    TopologyMapView(snapshot: ecosystem, config: model.config, selection: $selection).frame(height: 520)
                    if let selection, let node = TopologyLayout.build(ecosystem, config: model.config).nodes.first(where: { $0.id == selection }) {
                        TopologyInspector(node: node).frame(width: 280)
                    }
                }
                if !ecosystem.alerts.isEmpty { AlertList(alerts: ecosystem.alerts) }
                PathChain(hops: ecosystem.productPath)
                let metrics = summaryMetrics(ecosystem)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) { ForEach(metrics) { Readout($0) } }
            } else {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Midiendo el entorno por primera vez…").font(DaemonFont.mono).foregroundStyle(DaemonPalette.dim) }
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
    }

    func summaryMetrics(_ ecosystem: EcosystemSnapshot) -> [Metric] {
        let repos = model.repositories
        let core = Provenance(source: "núcleo C++", method: "git status --porcelain=v2", observedAt: model.snapshot.flatMap { $0.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) } } ?? Date())
        return [
            Metric(id: "repos", label: "Repos verificados", value: Double(repos.filter { $0.evidence == .verified }.count), display: "\(repos.filter { $0.evidence == .verified }.count) / \(repos.count)", provenance: core),
            Metric(id: "dirty", label: "Con cambios", value: Double(repos.filter { $0.dirty == true }.count), provenance: core),
            Metric(id: "services", label: "Sondas vivas", value: Double(ecosystem.services.filter(\.alive).count), display: "\(ecosystem.services.filter(\.alive).count) / \(ecosystem.services.count)",
                   provenance: Provenance(source: "sondas HTTP/TCP", method: "URLSession · Network", observedAt: ecosystem.observedAt)),
            Metric(id: "ports", label: "Listeners TCP", value: Double(ecosystem.ports.count), evidence: ecosystem.portsEvidence,
                   provenance: Provenance(source: "lsof", method: "-iTCP -sTCP:LISTEN", observedAt: ecosystem.observedAt)),
            Metric(id: "tailnet", label: "Tailnet", value: nil, display: ecosystem.tailnet.running ? "\(ecosystem.tailnet.peers.filter(\.online).count) en línea" : ecosystem.tailnet.backendState,
                   evidence: ecosystem.tailnet.evidence, provenance: ecosystem.tailnet.provenance),
            Metric(id: "cube", label: "Contrato del Cubo", value: nil, display: ecosystem.cubeExposure.status, evidence: ecosystem.cubeExposure.exposed ? .failed : (ecosystem.cubeExposure.safe ? .verified : .partial),
                   provenance: Provenance(source: "núcleo C++ check_exposure", method: ecosystem.cubeExposure.reason, observedAt: ecosystem.observedAt)),
        ]
    }
}

struct RepositoriesView: View {
    @ObservedObject var model: DaemonAppModel
    let session: AgentSession
    @State private var pendingPath = ""
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let path = model.selectedRepositoryPath, let repository = model.repositories.first(where: { $0.path == path }) {
                Button("‹ CATÁLOGO") { model.selectedRepositoryPath = nil }.buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                RepositoryWorkspaceView(repository: repository, allRepositories: model.repositories, session: session) { model.liveServices(for: $0) }
            } else {
                ScreenTitle(code: "03 · REPOSITORIOS", title: "Catálogo", subtitle: "Descubierto en \(model.config.workspaceRoot). Quitar una entrada nunca borra archivos.")
                HStack(spacing: 8) {
                    TextField("Ruta de un repositorio Git", text: $pendingPath).textFieldStyle(.plain).font(DaemonFont.mono)
                        .padding(8).overlay(Rectangle().stroke(DaemonPalette.line)).onSubmit(add)
                    Button { choosing = true } label: { Image(systemName: "folder") }.buttonStyle(.plain)
                    Button("AÑADIR", action: add).buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.green)
                    Button("DESCUBRIR") { model.discover(); Task { await model.refreshRepositories() } }.buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.green)
                    Button(model.refreshing ? "LEYENDO" : "ACTUALIZAR") { Task { await model.refreshRepositories() } }.buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                }
                if let error = model.error { Text(error).font(DaemonFont.mono).foregroundStyle(DaemonPalette.amber) }
                VStack(spacing: 0) {
                    ForEach(model.repositories) { repository in
                        HStack(spacing: 12) {
                            StatusDot(repository.evidence != .verified ? .unverified : (repository.dirty == true ? .partial : .verified))
                            Button(repository.name) { model.selectedRepositoryPath = repository.path }.buttonStyle(.plain).font(.system(size: 14)).frame(width: 170, alignment: .leading)
                            Text(repository.branch ?? "—").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.green).frame(width: 220, alignment: .leading).lineLimit(1)
                            Text(repository.head.map { String($0.prefix(7)) } ?? "—").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                            Text(repository.workingTreeLabel).font(DaemonFont.monoSmall).foregroundStyle(repository.dirty == true ? DaemonPalette.amber : DaemonPalette.dim)
                            Text(repository.comparisonLabel).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                            Spacer()
                            Button { model.removeRepository(repository.path) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                                .buttonStyle(.plain).foregroundStyle(DaemonPalette.faint).help("Quitar del catálogo (no borra archivos)")
                        }
                        .padding(.vertical, 10)
                        Rectangle().fill(DaemonPalette.grid).frame(height: 1)
                    }
                }
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addRepository(url.path); Task { await model.refreshRepositories() } }
        }
    }

    func add() {
        model.addRepository(pendingPath)
        pendingPath = ""
        Task { await model.refreshRepositories() }
    }
}

struct SystemView: View {
    @ObservedObject var model: DaemonAppModel
    @State private var machine = SystemProbe.machine()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScreenTitle(code: "04 · SISTEMA", title: machine.hostName, subtitle: "\(machine.model) · \(machine.osVersion) · lecturas nativas sin procesos externos")
            let gb = 1_073_741_824.0
            let p = machine.provenance
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                Readout(Metric(id: "cpu", label: "Carga 1/5/15 min", value: machine.loadAverage.first, display: machine.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " · "), provenance: p))
                Readout(Metric(id: "cores", label: "Núcleos activos", value: Double(machine.cpuCount), provenance: p))
                Readout(Metric(id: "ram", label: "Memoria usada", value: machine.memoryUsedBytes.map { Double($0) / gb },
                               display: machine.memoryUsedBytes.map { String(format: "%.1f / %.0f GB", Double($0) / gb, Double(machine.memoryTotalBytes) / gb) }, provenance: p))
                Readout(Metric(id: "disk", label: "Disco libre", value: machine.diskAvailableBytes.map { Double($0) / gb },
                               display: machine.diskAvailableBytes.map { String(format: "%.0f GB", Double($0) / gb) }, provenance: p))
                Readout(Metric(id: "uptime", label: "Uptime", value: machine.uptimeSeconds, display: String(format: "%.1f h", machine.uptimeSeconds / 3600), provenance: p))
                Readout(Metric(id: "thermal", label: "Térmico", value: nil, display: machine.thermalState, evidence: .verified, provenance: Provenance(source: "ProcessInfo.thermalState", method: "API de macOS")))
                if let battery = machine.battery {
                    Readout(Metric(id: "battery", label: "Batería", value: Double(battery.percent), display: "\(battery.percent) % · \(battery.source)", provenance: Provenance(source: "IOKit", method: "IOPSCopyPowerSourcesInfo")))
                }
            }
            if let ecosystem = model.ecosystem {
                PortTable(sockets: ecosystem.ports, declared: model.config.services)
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader("INTERFACES", trailing: "getifaddrs")
                ForEach(machine.interfaces) { interface in
                    HStack {
                        Text(interface.name).font(DaemonFont.monoSmall).frame(width: 90, alignment: .leading)
                        Text(interface.address).font(DaemonFont.monoSmall)
                        Spacer()
                        Text(interface.scope.label).font(DaemonFont.label).foregroundStyle(interface.scope == .tailnet ? DaemonPalette.cyan : DaemonPalette.dim)
                    }.padding(.vertical, 3)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                machine = SystemProbe.machine()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

struct NetworkView: View {
    @ObservedObject var model: DaemonAppModel
    let session: AgentSession
    let showAgent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScreenTitle(code: "05 · RED", title: "Tailnet y exposición", subtitle: "Preferencia: loopback › socket › túnel SSH › Tailscale › LAN › Internet.")
            if let ecosystem = model.ecosystem {
                TailnetTable(snapshot: ecosystem.tailnet)
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("CUBO DE NEO", "contrato 127.0.0.1:8765")
                    KeyValueRow("Veredicto del núcleo", "\(ecosystem.cubeExposure.status) · \(ecosystem.cubeExposure.reason)",
                                color: ecosystem.cubeExposure.exposed ? DaemonPalette.red : (ecosystem.cubeExposure.safe ? DaemonPalette.green : DaemonPalette.amber))
                    KeyValueRow("Túnel SSH", ecosystem.tunnelActive ? "activo (ssh escucha en 127.0.0.1:8765)" : "inactivo")
                    ForEach(ecosystem.status("neo-cube")) { status in KeyValueRow(status.machine.label, "\(status.endpoint ?? "—") · \(status.label)", color: DaemonPalette.color(status.evidence)) }
                    KeyValueRow("Usuario SSH del Desktop", model.config.desktopSSHUser ?? "sin configurar (topology.json)")
                    HStack(spacing: 8) {
                        ActionButton(action: AgentAction(title: "Abrir túnel al Desktop", tool: "cube.tunnel.open")) { session.perform(AgentAction(title: "Abrir túnel al Desktop", tool: "cube.tunnel.open")); showAgent() }
                        ActionButton(action: AgentAction(title: "Cerrar túnel", tool: "cube.tunnel.close")) { session.perform(AgentAction(title: "Cerrar túnel", tool: "cube.tunnel.close")); showAgent() }
                    }
                }
                let exposed = ecosystem.ports.filter { $0.scope != .loopback }
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("LISTENERS FUERA DE LOOPBACK", trailing: "\(exposed.count)")
                    if exposed.isEmpty { Text("Ninguno: todo escucha solo en este Mac.").font(DaemonFont.mono).foregroundStyle(DaemonPalette.green) }
                    ForEach(exposed) { socket in
                        HStack {
                            Text(":\(socket.port)").font(DaemonFont.mono).frame(width: 70, alignment: .leading)
                            Text(socket.command).font(DaemonFont.monoSmall).frame(width: 140, alignment: .leading)
                            Text(socket.address).font(DaemonFont.monoSmall)
                            Spacer()
                            Text(socket.scope.label).font(DaemonFont.label).foregroundStyle(socket.scope >= .allInterfaces ? DaemonPalette.amber : DaemonPalette.cyan)
                        }
                    }
                }
                Text("Topología declarada: ~/Library/Application Support/Daemon/topology.json").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
            }
        }
    }
}

struct TechnologyScreen: View {
    @ObservedObject var model: DaemonAppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScreenTitle(code: "06 · TECNOLOGÍA", title: "De qué está hecho Daemon", subtitle: "Versión y licencia solo desde fuentes locales verificables; el resto queda «no verificado».")
            TechnologyTable(tools: model.toolchain?.tools ?? [], registry: true)
            SectionHeader("MOTOR DE HERRAMIENTAS", "lo único que el agente puede invocar", trailing: "\(ToolCatalog.all.count) herramientas")
            VStack(spacing: 0) {
                ForEach(ToolCatalog.all) { spec in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(spec.name).font(DaemonFont.mono).foregroundStyle(DaemonPalette.green).frame(width: 170, alignment: .leading)
                        Text(spec.risk.rawValue).font(.system(size: 8, weight: .bold, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(spec.risk == .read ? DaemonPalette.faint : (spec.risk == .destructive ? DaemonPalette.red : DaemonPalette.amber)).foregroundStyle(Color.black)
                            .frame(width: 80, alignment: .leading)
                        Text(spec.description).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(spec.inputs.map { $0.name + ($0.required ? "*" : "") }.joined(separator: ", ")).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim).frame(width: 90, alignment: .leading)
                        Text(spec.technology).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).frame(width: 220, alignment: .leading)
                        Text(spec.requiresConfirmation ? "confirma" : "—").font(DaemonFont.label).foregroundStyle(spec.requiresConfirmation ? DaemonPalette.amber : DaemonPalette.faint).frame(width: 60)
                    }.padding(.vertical, 6)
                    Rectangle().fill(DaemonPalette.grid).frame(height: 1)
                }
            }
            SectionHeader("INVENTARIO DEL MAC", trailing: model.toolchain.map { DaemonClock.relative($0.observedAt) } ?? "midiendo")
            TechnologyTable(tools: model.toolchain?.tools ?? [])
        }
    }
}

struct SettingsSheet: View {
    let config: TopologyConfig
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var model = AgentSettings.model
    @State private var status = AgentKeychain.configured ? "API key guardada en el Llavero" : "Sin API key: el agente funciona en modo local"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AJUSTES").font(DaemonFont.label).tracking(2).foregroundStyle(DaemonPalette.green)
            Text("Adaptador LLM opcional").font(DaemonFont.heading)
            Text("Solo se usa cuando el router local no reconoce la intención. Ve únicamente herramientas de lectura y el índice compacto (context.json).")
                .font(.system(size: 12)).foregroundStyle(DaemonPalette.dim)
            SecureField("API key de Anthropic", text: $key).textFieldStyle(.roundedBorder)
            TextField("Modelo", text: $model).textFieldStyle(.roundedBorder)
            Text(status).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
            HStack {
                Button("Borrar key") { AgentKeychain.delete(); status = "API key eliminada del Llavero" }
                Spacer()
                Button("Cerrar") { dismiss() }
                Button("Guardar") {
                    AgentSettings.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty { status = AgentKeychain.save(key) ? "API key guardada en el Llavero" : "No se pudo guardar en el Llavero" }
                    key = ""
                }.keyboardShortcut(.defaultAction)
            }
            Divider()
            Text("Topología: ~/Library/Application Support/Daemon/topology.json · Desktop: \(config.desktopHost)").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
        }
        .padding(24).frame(width: 520)
    }
}
