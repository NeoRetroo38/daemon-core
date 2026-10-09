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
        ZStack(alignment: .bottomLeading) {
            SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Arrastra para orbitar · pellizca para ampliar")
                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.75)).padding(18)
        }.background(DaemonPalette.panel).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var scene: SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let metrics = Array(insights.languages.prefix(8))
        for (index, metric) in metrics.enumerated() {
            let height = max(0.35, CGFloat(metric.files) / CGFloat(max(metrics.first?.files ?? 1, 1)) * 3.6)
            let box = SCNBox(width: 0.62, height: height, length: 0.62, chamferRadius: 0.08)
            let material = SCNMaterial()
            material.diffuse.contents = NSColor(calibratedRed: 0.22, green: 1, blue: 0.08, alpha: 0.82)
            material.emission.contents = NSColor(calibratedRed: 0.04, green: 0.24, blue: 0.02, alpha: 1)
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(Float(index % 4) - 1.5, Float(height / 2), Float(index / 4) - 0.5)
            scene.rootNode.addChildNode(node)
        }
        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.04, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 4.5, 7)
        camera.eulerAngles.x = -.pi / 8
        scene.rootNode.addChildNode(camera)
        return scene
    }
}
