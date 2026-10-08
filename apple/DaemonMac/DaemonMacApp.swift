import DaemonKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacDashboardModel: ObservableObject {
    @Published var path: String
    @Published private(set) var snapshot: DaemonSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var refreshing = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--repo"), arguments.indices.contains(index + 1) {
            path = arguments[index + 1]
        } else {
            path = ""
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            snapshot = nil
            error = "Selecciona explícitamente un repositorio Git."
            return
        }
        refreshing = true
        error = nil
        let repositoryPath = path
        do {
            let value = try await Task.detached(priority: .userInitiated) {
                try CoreBridge.snapshot(repositoryPath: repositoryPath)
            }.value
            snapshot = value
        } catch {
            snapshot = nil
            self.error = error.localizedDescription
        }
        refreshing = false
    }
}

@main
struct DaemonMacApp: App {
    @StateObject private var model = MacDashboardModel()

    var body: some Scene {
        WindowGroup("Daemon") {
            MacDashboard(model: model)
                .frame(minWidth: 820, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1030, height: 780)
    }
}

struct MacDashboard: View {
    @ObservedObject var model: MacDashboardModel
    @State private var choosingDirectory = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAEMON").font(.system(size: 25, weight: .light, design: .monospaced)).tracking(3)
                    Text("Scenarys · consola nativa").font(.caption).foregroundStyle(.secondary)
                }
                Rectangle().fill(DaemonPalette.green).frame(width: 26, height: 2)
                Label("Repositorios", systemImage: "folder").font(.subheadline)
                Label("Evidencia local", systemImage: "checkmark.shield").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("CORE \(CoreBridge.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("Lectura manual\nSin control remoto").font(.caption).foregroundStyle(.secondary)
            }
            .padding(26)
            .frame(width: 190, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(DaemonPalette.panel)
            Rectangle().fill(DaemonPalette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    TextField("Ruta de un repositorio Git", text: $model.path)
                        .textFieldStyle(.plain).font(.caption.monospaced())
                        .padding(10).background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 7))
                        .onSubmit { Task { await model.refresh() } }
                    Button { choosingDirectory = true } label: { Image(systemName: "folder") }
                        .help("Elegir un repositorio")
                    Button(model.refreshing ? "Leyendo…" : "Actualizar") { Task { await model.refresh() } }
                        .disabled(model.refreshing).keyboardShortcut("r", modifiers: .command)
                }
                ScrollView {
                    if let snapshot = model.snapshot {
                        SnapshotDashboard(snapshot: snapshot).padding(.bottom, 20)
                    } else if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No verificado").font(.title.weight(.light))
                            Text(error).foregroundStyle(.secondary)
                            Text("Elige un repositorio y vuelve a actualizar.")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView("Leyendo el repositorio…").frame(maxWidth: .infinity, minHeight: 250)
                    }
                }
            }
            .padding(28)
        }
        .background(DaemonPalette.background)
        .task { await model.refresh() }
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.path = url.path
                Task { await model.refresh() }
            }
        }
    }
}
