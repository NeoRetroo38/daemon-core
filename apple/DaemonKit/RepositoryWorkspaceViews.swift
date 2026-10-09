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
                case "Mapa 3D": RepositorySceneView(insights: insights)
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
    public let insights: RepositoryInsights
    public init(insights: RepositoryInsights) { self.insights = insights }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Text("CUBO DE MÉTRICAS").font(.caption.monospaced()).foregroundStyle(DaemonPalette.green)
                Text("Código × Git × Operación").font(.title3.weight(.light)).foregroundStyle(.white)
                Text("27 celdas · densidad conjunta del repositorio").font(.caption).foregroundStyle(.white.opacity(0.65))
                Spacer()
                HStack(spacing: 14) {
                    legend("Código", value: codeScore)
                    legend("Git", value: gitScore)
                    legend("Operación", value: operationScore)
                }
                Text("Arrastra para orbitar · pellizca para ampliar")
                    .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.6))
            }.padding(18)
        }.background(DaemonPalette.panel).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var codeScore: Int { min(100, max(8, insights.sourceLines / 120)) }
    private var gitScore: Int { min(100, max(12, insights.fileCount / 2)) }
    private var operationScore: Int {
        min(100, insights.capabilities.count * 18 + (insights.hasDatabase ? 18 : 0) + (insights.hasLogin ? 14 : 0))
    }

    private func legend(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.65))
            Text("\(value)%").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.white)
        }
    }

    private var scene: SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let scores = [codeScore, gitScore, operationScore]
        let combined = max(1, scores.reduce(0, +) / scores.count)
        for x in 0..<3 {
            for y in 0..<3 {
                for z in 0..<3 {
                    let threshold = ((x + 1) * scores[0] + (y + 1) * scores[1] + (z + 1) * scores[2]) / 9
                    let active = threshold <= combined
                    let box = SCNBox(width: 0.68, height: 0.68, length: 0.68, chamferRadius: 0.075)
                    let material = SCNMaterial()
                    let energy = CGFloat(scores[(x + y + z) % 3]) / 100
                    material.diffuse.contents = NSColor(calibratedRed: 0.12 + energy * 0.12, green: active ? 0.78 + energy * 0.22 : 0.18, blue: 0.58 + energy * 0.32, alpha: active ? 0.86 : 0.16)
                    material.emission.contents = NSColor(calibratedRed: 0.02, green: active ? 0.17 + energy * 0.18 : 0.02, blue: active ? 0.15 : 0.04, alpha: 1)
                    material.transparency = active ? 0.92 : 0.28
                    material.metalness.contents = 0.35
                    material.roughness.contents = 0.28
                    box.materials = [material]
                    let node = SCNNode(geometry: box)
                    node.position = SCNVector3(Float(x - 1) * 0.88, Float(y) * 0.88 + 0.36, Float(z - 1) * 0.88)
                    scene.rootNode.addChildNode(node)
                }
            }
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
}
