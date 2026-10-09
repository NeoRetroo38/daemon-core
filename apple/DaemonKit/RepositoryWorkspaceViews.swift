import SceneKit
import SwiftUI

public struct RepositoryWorkspaceView: View {
    public let repository: RepositorySnapshot
    @State private var insights: RepositoryInsights = .empty
    @State private var loading = true
    @State private var diagnosticStates: [String: DiagnosticState] = [:]
    @State private var selectedTab = "Métricas"

    public init(repository: RepositorySnapshot) { self.repository = repository }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name).font(.system(size: 30, weight: .light))
                    Text(repository.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                EvidenceBadge(repository.evidence)
            }
            Picker("Vista", selection: $selectedTab) {
                ForEach(["Métricas", "Pruebas", "Mapa 3D", "Agente"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case "Pruebas": diagnostics
                case "Mapa 3D": RepositorySceneView(repository: repository, insights: insights)
                case "Agente": ProjectAgentView(repository: repository, insights: insights)
                default: metrics
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: repository.path) {
            loading = true
            insights = await Task.detached { RepositoryInspector.inspect(path: repository.path) }.value
            loading = false
        }
    }

    private var metrics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    metric("ARCHIVOS", loading ? "…" : "\(insights.fileCount)")
                    metric("LÍNEAS", loading ? "…" : insights.sourceLines.formatted())
                    metric("TAMAÑO", ByteCountFormatter.string(fromByteCount: insights.bytes, countStyle: .file))
                    metric("ESTADO", repository.workingTreeLabel)
                }
                panel("Tecnologías detectadas") {
                    FlowLayout(items: insights.capabilities)
                }
                panel("Distribución del código") {
                    VStack(spacing: 10) {
                        ForEach(insights.languages) { language in
                            HStack {
                                Text(language.name).frame(width: 100, alignment: .leading)
                                GeometryReader { proxy in
                                    let maximum = max(insights.languages.first?.files ?? 1, 1)
                                    Capsule().fill(DaemonPalette.green.opacity(0.75))
                                        .frame(width: proxy.size.width * CGFloat(language.files) / CGFloat(maximum), height: 8)
                                }.frame(height: 8)
                                Text("\(language.files)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if insights.hasLogin && insights.hasDatabase {
                    panel("Registros de usuario · datos minimizados") {
                        if insights.usernames.isEmpty {
                            Text("Login y base de datos detectados. No hay nombres disponibles en el almacén local autorizado.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(insights.usernames, id: \.self) { username in
                                    Label(username, systemImage: "person.crop.circle")
                                        .font(.system(.body, design: .rounded))
                                }
                            }
                        }
                        Text("Solo se lee displayName; Daemon descarta correo, identificadores, roles, hashes y sesiones.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                panel("Estudio creativo local") {
                    HStack(spacing: 24) {
                        capability("Blender", available: insights.blenderAvailable, purpose: "modelado y exportación 3D")
                        capability("Ableton Live Lite", available: insights.abletonAvailable, purpose: "audio reactivo y diseño sonoro")
                    }
                }
            }
        }
    }

    private var diagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pruebas de solo lectura").font(.title2.weight(.light))
                Text("No ejecutan shell, no escriben archivos y las sondas de red están limitadas a loopback.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(DiagnosticCatalog.diagnostics(for: repository.path)) { diagnostic in
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.shield").foregroundStyle(DaemonPalette.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(diagnostic.title).font(.headline.weight(.regular))
                            Text(diagnostic.detail).font(.caption).foregroundStyle(.secondary)
                            Text(diagnosticStates[diagnostic.id]?.label ?? DiagnosticState.ready.label)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Probar") { run(diagnostic) }
                            .disabled(ifRunning(diagnostic.id))
                    }
                    .padding(16).background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DaemonPalette.line))
                }
            }
        }
    }

    private func run(_ diagnostic: RepositoryDiagnostic) {
        diagnosticStates[diagnostic.id] = .running
        Task { diagnosticStates[diagnostic.id] = await DiagnosticCatalog.run(diagnostic) }
    }

    private func ifRunning(_ id: String) -> Bool {
        if case .running? = diagnosticStates[id] { return true }
        return false
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .light, design: .monospaced)).foregroundStyle(DaemonPalette.green).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DaemonPalette.line))
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline.weight(.regular))
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DaemonPalette.line))
    }

    private func capability(_ title: String, available: Bool, purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: available ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(available ? DaemonPalette.green : .secondary)
            Text(available ? "Disponible · \(purpose)" : "No detectado en /Applications")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.caption.monospaced()).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(DaemonPalette.green.opacity(0.1), in: Capsule())
                    .overlay(Capsule().stroke(DaemonPalette.green.opacity(0.35)))
            }
        }
    }
}

public struct RepositorySceneView: View {
    public let repository: RepositorySnapshot
    public let insights: RepositoryInsights
    public init(repository: RepositorySnapshot, insights: RepositoryInsights) {
        self.repository = repository
        self.insights = insights
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Text("CUBO DE MÉTRICAS").font(.caption.monospaced()).foregroundStyle(DaemonPalette.green)
                Text("x código · y repositorio · z capacidad").font(.title3.weight(.light)).foregroundStyle(.white)
                Text("4 recorridos · 12 medidas · escala discreta 1 → 3").font(.caption).foregroundStyle(.white.opacity(0.65))
                Spacer()
                HStack(spacing: 18) {
                    ForEach(metricRuns, id: \.name) { run in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.name).font(.caption2).foregroundStyle(run.color)
                            Text("\(run.x) · \(run.y) · \(run.z)").font(.caption.monospaced()).foregroundStyle(.white)
                        }
                    }
                }
                Text("Arrastra para orbitar · pellizca para ampliar")
                    .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.6))
            }.padding(18)
        }.background(DaemonPalette.panel).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private struct MetricRun {
        let name: String
        let x: Int
        let y: Int
        let z: Int
        let color: Color
    }

    private var metricRuns: [MetricRun] {
        let density = level(insights.sourceLines, 3_000, 15_000)
        let breadth = level(insights.fileCount, 60, 220)
        let languages = level(insights.languages.count, 2, 5)
        let git = repository.dirty == false ? 3 : (repository.dirty == true ? 1 : 2)
        let sync = (repository.ahead ?? 0) == 0 && (repository.behind ?? 0) == 0 ? 3 : 1
        let upstream = repository.upstream == nil ? 1 : 3
        let runtime = level(insights.capabilities.count, 1, 3)
        let persistence = insights.hasDatabase ? 3 : (insights.hasLogin ? 2 : 1)
        let creative = (insights.blenderAvailable ? 1 : 0) + (insights.abletonAvailable ? 1 : 0) + 1
        let scale = level(Int(insights.bytes), 500_000, 4_000_000)
        let users = level(insights.usernames.count, 0, 4)
        let tooling = level(insights.capabilities.count + insights.languages.count, 4, 9)
        return [
            MetricRun(name: "Código", x: density, y: breadth, z: languages, color: .white),
            MetricRun(name: "Git", x: git, y: sync, z: upstream, color: .red),
            MetricRun(name: "Runtime", x: runtime, y: persistence, z: min(3, creative), color: DaemonPalette.green),
            MetricRun(name: "Escala", x: scale, y: users, z: tooling, color: .orange),
        ]
    }

    private func level(_ value: Int, _ medium: Int, _ high: Int) -> Int {
        value >= high ? 3 : (value >= medium ? 2 : 1)
    }

    private var scene: SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let wire = NSColor(calibratedWhite: 0.62, alpha: 0.42)
        for a in [-1.5 as Float, 0, 1.5] {
            for b in [-1.5 as Float, 0, 1.5] {
                addLine(to: scene, from: SCNVector3(-1.5, a, b), to: SCNVector3(1.5, a, b), color: wire, radius: 0.008)
                addLine(to: scene, from: SCNVector3(a, -1.5, b), to: SCNVector3(a, 1.5, b), color: wire, radius: 0.008)
                addLine(to: scene, from: SCNVector3(a, b, -1.5), to: SCNVector3(a, b, 1.5), color: wire, radius: 0.008)
            }
        }
        let colors: [NSColor] = [.white, .systemRed, NSColor(calibratedRed: 0.22, green: 1, blue: 0.08, alpha: 1), .systemOrange]
        for (index, run) in metricRuns.enumerated() {
            let points = [
                SCNVector3(coordinate(run.x), coordinate(run.y), -1.5),
                SCNVector3(coordinate(run.x), coordinate(run.y), coordinate(run.z)),
                SCNVector3(-1.5, coordinate(run.y), coordinate(run.z)),
            ]
            for point in points {
                let sphere = SCNSphere(radius: index == 0 ? 0.09 : 0.065)
                sphere.firstMaterial?.diffuse.contents = colors[index]
                sphere.firstMaterial?.emission.contents = colors[index]
                let node = SCNNode(geometry: sphere)
                node.position = point
                scene.rootNode.addChildNode(node)
            }
            addLine(to: scene, from: points[0], to: points[1], color: colors[index], radius: index == 0 ? 0.035 : 0.018)
            addLine(to: scene, from: points[1], to: points[2], color: colors[index], radius: index == 0 ? 0.035 : 0.018)
        }
        let floor = SCNFloor()
        floor.reflectivity = 0.22
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.04, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 44
        camera.position = SCNVector3(4.8, 4.4, 6.8)
        let constraint = SCNLookAtConstraint(target: scene.rootNode)
        constraint.isGimbalLockEnabled = true
        camera.constraints = [constraint]
        scene.rootNode.addChildNode(camera)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = NSColor(calibratedRed: 0.35, green: 0.9, blue: 1, alpha: 1)
        light.light?.intensity = 900
        light.position = SCNVector3(-3, 6, 4)
        scene.rootNode.addChildNode(light)
        return scene
    }

    private func coordinate(_ value: Int) -> Float { Float(value - 2) * 1.5 }

    private func addLine(to scene: SCNScene, from start: SCNVector3, to end: SCNVector3, color: NSColor, radius: CGFloat) {
        let vector = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.emission.contents = color.withAlphaComponent(0.35)
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
        node.look(at: end, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(node)
    }
}
