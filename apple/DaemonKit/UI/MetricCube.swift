import Foundation
#if os(macOS)
import AppKit
import SceneKit
import SwiftUI
#endif

/// Una medida del cubo: misma forma pública que el Cubo de Neo
/// (fase, fila, columna; base 1), aplicada a métricas de ingeniería.
/// No reutiliza ninguna lógica privada del motor: solo su lenguaje visual.
public struct CubeMeasurement: Sendable, Hashable, Identifiable {
    public let phase: Int
    public let row: Int
    public let column: Int
    public let phaseName: String
    public let rowMetric: Metric
    public let columnMetric: Metric
    public var id: String { "\(phase)-\(row)-\(column)-\(rowMetric.id)" }
}

public struct CubeRun: Sendable, Hashable, Identifiable {
    public let repository: String
    public let measurements: [CubeMeasurement]
    public var id: String { repository }
}

public enum CubeModel {
    public static let phases = ["CÓDIGO", "GIT", "OPERACIÓN"]
    public static let axes = [("tamaño", "amplitud"), ("actividad", "divergencia"), ("tests", "servicios vivos")]

    /// Escala discreta 1…3 con umbrales explícitos (se muestran en el inspector).
    public static func level(_ value: Double?, _ medium: Double, _ high: Double) -> Int {
        guard let value else { return 1 }
        return value >= high ? 3 : (value >= medium ? 2 : 1)
    }

    public static func run(record: RepositoryRecord, repository: RepositorySnapshot, liveServices: Int?) -> CubeRun {
        let scan = Provenance(source: record.reused ? "índice local" : "escaneo local", method: "FileManager (sin .git, builds ni dependencias)", observedAt: record.scannedAt)
        let git = record.git.provenance
        let divergence = Double(record.git.workingChanges.count + (record.git.untrackedCount ?? 0) + (repository.ahead ?? 0) + (repository.behind ?? 0))
        func metric(_ id: String, _ label: String, _ value: Double?, _ provenance: Provenance, _ thresholds: (Double, Double)) -> Metric {
            Metric(id: id, label: label, value: value,
                   display: value.map { "\(Metric.format($0)) → nivel \(level($0, thresholds.0, thresholds.1)) (umbrales \(Metric.format(thresholds.0))/\(Metric.format(thresholds.1)))" },
                   provenance: provenance)
        }
        let lines = metric("lines", "Líneas de código", Double(record.insights.sourceLines), scan, (3_000, 15_000))
        let languages = metric("languages", "Lenguajes", Double(record.insights.languages.count), scan, (3, 5))
        let week = metric("week", "Commits 7 días", record.git.commitsLast7Days.map(Double.init), git, (1, 10))
        let diverge = metric("divergence", "Cambios + ahead + behind", divergence, git, (1, 10))
        let tests = metric("tests", "Archivos de test", Double(record.insights.testFiles), scan, (1, 10))
        let services = metric("services", "Servicios vivos", liveServices.map(Double.init),
                              Provenance(source: "sondas de Daemon", method: "HTTP/TCP a servicios declarados del repo"), (1, 2))
        return CubeRun(repository: repository.name, measurements: [
            CubeMeasurement(phase: 1, row: level(lines.value, 3_000, 15_000), column: level(languages.value, 3, 5), phaseName: phases[0], rowMetric: lines, columnMetric: languages),
            CubeMeasurement(phase: 2, row: level(week.value, 1, 10), column: level(divergence, 1, 10), phaseName: phases[1], rowMetric: week, columnMetric: diverge),
            CubeMeasurement(phase: 3, row: level(tests.value, 1, 10), column: level(services.value, 1, 2), phaseName: phases[2], rowMetric: tests, columnMetric: services),
        ])
    }
}

#if os(macOS)
public struct MetricCubeView: NSViewRepresentable {
    let runs: [CubeRun]
    @Binding var selection: CubeMeasurement?

    public init(runs: [CubeRun], selection: Binding<CubeMeasurement?>) {
        self.runs = runs
        self._selection = selection
    }

    /// Primer recorrido en blanco (como en el visor del Cubo); comparados en lila, verde y crema.
    public static let runColors: [NSColor] = [
        .white, NSColor(calibratedRed: 0.72, green: 0.6, blue: 1, alpha: 1), NSColor(calibratedRed: 0.22, green: 1, blue: 0.08, alpha: 1),
        NSColor(calibratedRed: 0.93, green: 0.9, blue: 0.79, alpha: 1), .systemOrange, .systemTeal,
    ]

    public func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    public func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.scene = scene(context.coordinator)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        view.addGestureRecognizer(click)
        return view
    }

    public func updateNSView(_ view: SCNView, context: Context) {
        let signature = runs.map { $0.measurements.map(\.id).joined() }.joined(separator: "|")
        if context.coordinator.signature != signature { view.scene = scene(context.coordinator) }
        context.coordinator.highlight(selection, in: view.scene)
    }

    /// Fila y columna 1…3 → coordenada en la cara; fase 1…3 → profundidad.
    func coordinate(_ value: Int) -> CGFloat { CGFloat(value - 2) * 1.0 }

    func scene(_ coordinator: Coordinator) -> SCNScene {
        coordinator.signature = runs.map { $0.measurements.map(\.id).joined() }.joined(separator: "|")
        coordinator.measurements = [:]
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let root = scene.rootNode
        let edge: CGFloat = 1.5
        let gray = NSColor(calibratedWhite: 0.36, alpha: 1)
        let green = NSColor(calibratedRed: 0.22, green: 1, blue: 0.08, alpha: 1)
        let red = NSColor(calibratedRed: 0.85, green: 0.16, blue: 0.14, alpha: 1)
        // Retícula 3×3×3 alámbrica, fina: el visor del Cubo de Neo.
        let ticks: [CGFloat] = [-edge, -edge / 3, edge / 3, edge]
        for a in ticks { for b in ticks {
            let outer = (abs(a) == edge ? 1 : 0) + (abs(b) == edge ? 1 : 0)
            let color = outer == 2 ? NSColor(calibratedWhite: 0.55, alpha: 1) : gray
            let radius: CGFloat = outer == 2 ? 0.006 : 0.0035
            line(root, SCNVector3(-edge, a, b), SCNVector3(edge, a, b), color, radius)
            line(root, SCNVector3(a, -edge, b), SCNVector3(a, edge, b), color, radius)
            line(root, SCNVector3(a, b, -edge), SCNVector3(a, b, edge), color, radius)
        } }
        // Diagonales rojas de referencia (cara trasera y diagonal espacial).
        line(root, SCNVector3(-edge, edge, -edge), SCNVector3(edge, -edge, -edge), red, 0.005)
        line(root, SCNVector3(-edge, -edge, -edge), SCNVector3(edge, edge, -edge), red, 0.005)
        line(root, SCNVector3(-edge, edge, edge), SCNVector3(edge, -edge, -edge), red.withAlphaComponent(0.6), 0.004)
        // Ejes verdes con su nombre: x col, y row, z phase.
        let reach = edge * 1.22
        line(root, SCNVector3(-reach, 0, 0), SCNVector3(reach, 0, 0), green, 0.011)
        line(root, SCNVector3(0, -reach, 0), SCNVector3(0, reach, 0), green, 0.011)
        line(root, SCNVector3(0, 0, -reach), SCNVector3(0, 0, reach), green, 0.011)
        label(root, "x col", at: SCNVector3(reach + 0.08, 0.04, 0), color: green, size: 0.13)
        label(root, "y row", at: SCNVector3(0.06, -reach - 0.22, 0), color: green, size: 0.13)
        label(root, "z phase", at: SCNVector3(0.06, 0.04, reach + 0.08), color: green, size: 0.13)
        for (index, name) in CubeModel.phases.enumerated() {
            label(root, "f\(index + 1) \(name.lowercased())", at: SCNVector3(-edge - 0.05, edge + 0.08, coordinate(index + 1)),
                  color: NSColor(calibratedWhite: 0.5, alpha: 1), size: 0.09)
        }
        // Recorridos: una trayectoria por repositorio, vértices numerados 1 → 3.
        for (runIndex, run) in runs.enumerated() {
            let color = Self.runColors[runIndex % Self.runColors.count]
            let offset = CGFloat(runIndex) * 0.07 - CGFloat(runs.count - 1) * 0.035
            var previous: SCNVector3?
            for measurement in run.measurements {
                let position = SCNVector3(coordinate(measurement.column) + offset, -coordinate(measurement.row) + offset, coordinate(measurement.phase))
                let sphere = SCNSphere(radius: 0.065)
                sphere.firstMaterial?.diffuse.contents = color
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.position = position
                let key = "\(run.repository)#\(measurement.id)"
                node.name = key
                coordinator.measurements[key] = measurement
                root.addChildNode(node)
                // Halo de selección (invisible hasta que se selecciona).
                let halo = SCNNode(geometry: SCNSphere(radius: 0.12))
                halo.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.18)
                halo.geometry?.firstMaterial?.lightingModel = .constant
                halo.name = "halo:" + key
                halo.isHidden = true
                node.addChildNode(halo)
                label(root, "\(measurement.phase)", at: SCNVector3(position.x + 0.09, position.y - 0.05, position.z), color: color, size: 0.11)
                if let previous { line(root, previous, position, color, runIndex == 0 ? 0.016 : 0.011) }
                previous = position
            }
            label(root, run.repository, at: SCNVector3(edge + 0.15, edge - CGFloat(runIndex) * 0.24, -edge), color: color, size: 0.12)
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(3.9, 2.6, 5.4)
        let look = SCNLookAtConstraint(target: root)
        look.isGimbalLockEnabled = true
        camera.constraints = [look]
        root.addChildNode(camera)
        return scene
    }

    func line(_ root: SCNNode, _ a: SCNVector3, _ b: SCNVector3, _ color: NSColor, _ radius: CGFloat) {
        let vector = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0.0001 else { return }
        let cylinder = SCNCylinder(radius: radius, height: length)
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.emission.contents = color
        cylinder.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        node.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        root.addChildNode(node)
    }

    func label(_ root: SCNNode, _ text: String, at position: SCNVector3, color: NSColor, size: CGFloat = 0.16) {
        let geometry = SCNText(string: text, extrusionDepth: 0)
        geometry.font = NSFont.monospacedSystemFont(ofSize: 1, weight: .regular)
        geometry.flatness = 0.05
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: geometry)
        node.scale = SCNVector3(size, size, size)
        node.position = position
        node.constraints = [SCNBillboardConstraint()]
        root.addChildNode(node)
    }

    @MainActor
    public final class Coordinator: NSObject {
        var selection: Binding<CubeMeasurement?>
        var measurements: [String: CubeMeasurement] = [:]
        var signature = ""
        init(selection: Binding<CubeMeasurement?>) { self.selection = selection }

        @objc func clicked(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            let hit = hits.first { $0.node.name.flatMap { measurements[$0] } != nil }
            selection.wrappedValue = hit.flatMap { $0.node.name.flatMap { measurements[$0] } }
        }

        func highlight(_ selected: CubeMeasurement?, in scene: SCNScene?) {
            scene?.rootNode.enumerateChildNodes { node, _ in
                guard let name = node.name, name.hasPrefix("halo:"), let measurement = measurements[String(name.dropFirst(5))] else { return }
                node.isHidden = measurement != selected
            }
        }
    }
}

/// Cubo + inspector de procedencia. Se usa en el chat y en el workspace.
public struct MetricCubePanel: View {
    let runs: [CubeRun]
    var height: CGFloat
    @State private var selection: CubeMeasurement?

    public init(runs: [CubeRun], height: CGFloat = 360) {
        self.runs = runs
        self.height = height
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            MetricCubeView(runs: runs, selection: $selection)
            VStack(alignment: .leading, spacing: 4) {
                Text("CUBO DE MÉTRICAS").font(DaemonFont.label).tracking(1.4).foregroundStyle(DaemonPalette.green)
                Text("fase 1 código · fase 2 git · fase 3 operación").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
            }.padding(12).allowsHitTesting(false)
            VStack(spacing: 3) {
                Spacer()
                Text("last \(runs.count) \(runs.count == 1 ? "run" : "runs")").font(.system(size: 11, design: .monospaced)).foregroundStyle(DaemonPalette.green)
                Text("drag to rotate · scroll to zoom · click a point · phase 1 → 3").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim)
            }.frame(maxWidth: .infinity).padding(.bottom, 10).allowsHitTesting(false)
            if let selection {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("FASE \(selection.phase) · \(selection.phaseName)").font(DaemonFont.label).foregroundStyle(DaemonPalette.green); Spacer()
                        Text("(\(selection.phase), \(selection.row), \(selection.column))").font(DaemonFont.label).foregroundStyle(DaemonPalette.dim) }
                    ForEach([("FILA", selection.rowMetric), ("COLUMNA", selection.columnMetric)], id: \.0) { axis, metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(axis) · \(metric.label)").font(DaemonFont.label).foregroundStyle(DaemonPalette.ink)
                            Text(metric.display).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.color(metric.evidence))
                            Text("fuente \(metric.provenance.source) · \(metric.provenance.method)").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.dim)
                            Text("observado \(DaemonClock.iso(metric.provenance.observedAt)) · \(metric.evidence.label)").font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.faint)
                        }
                    }
                }
                .frame(width: 300).padding(12).background(Color.black.opacity(0.88)).overlay(Rectangle().stroke(DaemonPalette.line))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
            }
        }
        .frame(height: height)
        .overlay(Rectangle().stroke(DaemonPalette.line))
        .cornerBrackets()
    }
}
#endif
