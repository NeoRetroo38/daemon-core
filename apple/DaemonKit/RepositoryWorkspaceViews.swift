#if os(macOS)
import SwiftUI

/// Espacio de trabajo por repositorio, alimentado por el índice local.
public struct RepositoryWorkspaceView: View {
    public let repository: RepositorySnapshot
    let allRepositories: [RepositorySnapshot]
    let session: AgentSession
    let liveServices: (String) -> Int?
    @State private var record: RepositoryRecord?
    @State private var others: [String: RepositoryRecord] = [:]
    @State private var comparing: Set<String> = []
    @State private var diagnosticStates: [String: DiagnosticState] = [:]
    @State private var selectedTab = "Métricas"
    @State private var refreshing = false

    public init(repository: RepositorySnapshot, allRepositories: [RepositorySnapshot], session: AgentSession, liveServices: @escaping (String) -> Int?) {
        self.repository = repository
        self.allRepositories = allRepositories
        self.session = session
        self.liveServices = liveServices
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(spacing: 0) {
                ForEach(["Métricas", "Git", "Cubo 3D", "Pruebas"], id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 6) {
                            Text(tab.uppercased()).font(DaemonFont.label).tracking(1.4)
                                .foregroundStyle(selectedTab == tab ? DaemonPalette.ink : DaemonPalette.dim)
                            Rectangle().fill(selectedTab == tab ? DaemonPalette.green : Color.clear).frame(height: 2)
                        }.padding(.trailing, 22)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            Group {
                switch selectedTab {
                case "Git": git
                case "Cubo 3D": cube
                case "Pruebas": diagnostics
                default: metrics
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: repository.path + (repository.head ?? "")) { await load(force: false) }
    }

    func load(force: Bool) async {
        refreshing = true
        record = await RepositoryIndex.shared.record(for: repository, force: force)
        refreshing = false
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(repository.name).font(DaemonFont.title)
                Spacer()
                EvidenceTag(repository.evidence == .verified ? .verified : .unverified)
            }
            HStack(spacing: 18) {
                Text(repository.branch ?? "rama no verificada").font(DaemonFont.mono).foregroundStyle(DaemonPalette.green)
                Text(repository.head.map { String($0.prefix(10)) } ?? "—").font(DaemonFont.mono).foregroundStyle(DaemonPalette.dim)
                Text(repository.workingTreeLabel).font(DaemonFont.mono).foregroundStyle(repository.dirty == true ? DaemonPalette.amber : DaemonPalette.dim)
                Text(repository.comparisonLabel).font(DaemonFont.mono).foregroundStyle(DaemonPalette.dim)
                Spacer()
                if let record {
                    Text(record.reused ? "índice reutilizado · \(DaemonClock.relative(record.scannedAt))" : "escaneado en \(record.scanMs) ms")
                        .font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                }
                Button(refreshing ? "LEYENDO" : "REESCANEAR") { Task { await load(force: true) } }
                    .buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).disabled(refreshing)
            }
            Text(repository.path).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint).textSelection(.enabled)
        }
    }

    var metrics: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let record {
                let scan = Provenance(source: record.reused ? "índice local" : "escaneo local", method: "FileManager", observedAt: record.scannedAt)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    Readout(Metric(id: "files", label: "Archivos", value: Double(record.insights.fileCount), provenance: scan))
                    Readout(Metric(id: "lines", label: "Líneas", value: Double(record.insights.sourceLines), display: record.insights.sourceLines.formatted(), provenance: scan))
                    Readout(Metric(id: "size", label: "Tamaño", value: Double(record.insights.bytes), display: ByteCountFormatter.string(fromByteCount: record.insights.bytes, countStyle: .file), provenance: scan))
                    Readout(Metric(id: "tests", label: "Archivos de test", value: Double(record.insights.testFiles), provenance: scan))
                    Readout(Metric(id: "commits", label: "Commits", value: record.git.commitCount.map(Double.init), provenance: record.git.provenance))
                    Readout(Metric(id: "week", label: "Commits 7 días", value: record.git.commitsLast7Days.map(Double.init), provenance: record.git.provenance))
                    Readout(Metric(id: "branches", label: "Ramas", value: record.git.branchCount.map(Double.init), provenance: record.git.provenance))
                    Readout(Metric(id: "changed", label: "Cambios locales", value: Double(record.git.workingChanges.count + (record.git.untrackedCount ?? 0)), provenance: record.git.provenance))
                }
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("LENGUAJES", trailing: "archivos")
                        ForEach(record.insights.languages) { language in
                            HStack {
                                Text(language.name).font(DaemonFont.monoSmall).frame(width: 90, alignment: .leading)
                                GeometryReader { proxy in
                                    let maximum = max(record.insights.languages.first?.files ?? 1, 1)
                                    Rectangle().fill(DaemonPalette.green.opacity(0.7)).frame(width: proxy.size.width * CGFloat(language.files) / CGFloat(maximum), height: 4)
                                        .frame(maxHeight: .infinity, alignment: .center)
                                }.frame(height: 10)
                                Text("\(language.files)").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim).frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("STACK")
                        FlowTags(items: record.insights.capabilities + record.insights.packageManagers)
                        SectionHeader("BUILD / TEST")
                        ForEach(record.insights.buildCommands, id: \.self) { Text($0).font(DaemonFont.monoSmall) }
                        SectionHeader("ARCHIVOS MÁS GRANDES")
                        ForEach(record.insights.largestFiles, id: \.self) { Text($0).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim).lineLimit(1).truncationMode(.middle) }
                    }
                }
                if record.insights.hasLogin && record.insights.hasDatabase {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("USUARIOS", "datos minimizados")
                        Text(record.insights.usernames.isEmpty ? "Login y base de datos detectados. Sin nombres en el almacén local autorizado." : record.insights.usernames.joined(separator: " · "))
                            .font(DaemonFont.monoSmall)
                        Text("Solo displayName; correo, IDs, roles, hashes y sesiones se descartan.").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                    }
                }
            } else {
                ProgressView("Leyendo el índice local…").frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    var git: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let record {
                if !record.git.workingChanges.isEmpty { BlockView(block: .changes(record.git.workingChanges), session: session, config: .standard, liveServices: liveServices) }
                CommitTimeline(commits: record.git.recent, title: "recientes")
                if let github = record.github {
                    BlockView(block: .pullRequests(github.pullRequests, slug: github.slug), session: session, config: .standard, liveServices: liveServices)
                    Text("GitHub · \(DaemonClock.relative(github.provenance.observedAt)) · \(github.evidence.label)").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                }
                HStack(spacing: 8) {
                    ActionButton(action: AgentAction(title: "Consultar PRs", tool: "github.prs", arguments: ["repo": repository.name])) { ask("¿Qué PRs tiene \(repository.name)?") }
                    ActionButton(action: AgentAction(title: "Ver diff", tool: "repo.diff", arguments: ["repo": repository.name])) { ask("Muéstrame el diff de \(repository.name)") }
                }
            }
        }
    }

    var cube: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record {
                let runs = [CubeModel.run(record: record, repository: repository, liveServices: liveServices(repository.name))] +
                    allRepositories.filter { comparing.contains($0.path) }.compactMap { other in
                        others[other.path].map { CubeModel.run(record: $0, repository: other, liveServices: liveServices(other.name)) }
                    }
                MetricCubePanel(runs: runs, height: 470)
                HStack(spacing: 8) {
                    Text("COMPARAR").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                    ForEach(allRepositories.filter { $0.path != repository.path }) { other in
                        let on = comparing.contains(other.path)
                        Button(other.name) {
                            if on { comparing.remove(other.path) } else {
                                comparing.insert(other.path)
                                Task { others[other.path] = await RepositoryIndex.shared.record(for: other) }
                            }
                        }
                        .buttonStyle(.plain).font(DaemonFont.monoSmall)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(on ? Color.black : DaemonPalette.ink).background(on ? DaemonPalette.green : Color.clear)
                        .overlay(Rectangle().stroke(DaemonPalette.line))
                    }
                }
                Text("Cada repositorio es un recorrido de 3 fases. Fila y columna son niveles 1–3 de dos métricas por fase; los umbrales y la procedencia aparecen al seleccionar un punto.")
                    .font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
            }
        }
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("PRUEBAS", "estructura y sondas")
            ForEach(DiagnosticCatalog.diagnostics(for: repository.path)) { diagnostic in
                HStack(spacing: 14) {
                    StatusDot(state(diagnosticStates[diagnostic.id]))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.title).font(.system(size: 13))
                        Text(diagnostic.detail).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
                    }
                    Spacer()
                    Text(diagnosticStates[diagnostic.id]?.label ?? DiagnosticState.ready.label).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.dim)
                    Button("PROBAR") {
                        diagnosticStates[diagnostic.id] = .running
                        Task { diagnosticStates[diagnostic.id] = await DiagnosticCatalog.run(diagnostic) }
                    }.buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.green)
                }
                .padding(.vertical, 8)
                Rectangle().fill(DaemonPalette.grid).frame(height: 1)
            }
            HStack {
                ActionButton(action: AgentAction(title: "Ejecutar la batería de tests", tool: "repo.tests", arguments: ["repo": repository.name])) {
                    ask("Ejecuta los tests de \(repository.name)")
                }
                Text("Se ejecuta desde el chat de Daemon para que quede el registro.").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
            }.padding(.top, 8)
        }
    }

    func state(_ value: DiagnosticState?) -> Evidence {
        switch value {
        case .passed?: .verified
        case .failed?: .failed
        default: .unverified
        }
    }

    func ask(_ text: String) {
        session.send(text)
        NotificationCenter.default.post(name: .daemonShowAgent, object: nil)
    }
}

extension Notification.Name {
    public static let daemonShowAgent = Notification.Name("daemon.showAgent")
}
#endif
