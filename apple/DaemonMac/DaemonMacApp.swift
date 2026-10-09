import DaemonKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacDashboardModel: ObservableObject {
    @Published private(set) var repositoryPaths: [String]
    @Published private(set) var snapshot: DaemonSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var refreshing = false

    private static let catalogKey = "daemon.repositoryCatalog.v1"

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--repo"), arguments.indices.contains(index + 1) {
            repositoryPaths = [arguments[index + 1]]
        } else {
            repositoryPaths = UserDefaults.standard.stringArray(forKey: Self.catalogKey) ?? []
        }
    }

    func addRepository(_ rawPath: String) {
        let path = (rawPath as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !repositoryPaths.contains(path) else { return }
        repositoryPaths.append(path)
        persistCatalog()
    }

    func removeRepository(_ path: String) {
        repositoryPaths.removeAll { $0 == path }
        persistCatalog()
        snapshot = nil
        error = repositoryPaths.isEmpty ? "Añade al catálogo uno o más repositorios Git." : nil
    }

    private func persistCatalog() {
        UserDefaults.standard.set(repositoryPaths, forKey: Self.catalogKey)
    }

    func refresh() async {
        guard !refreshing else { return }
        guard !repositoryPaths.isEmpty else {
            snapshot = nil
            error = "Añade al catálogo uno o más repositorios Git."
            return
        }
        refreshing = true
        error = nil
        let paths = repositoryPaths
        do {
            let value = try await Task.detached(priority: .userInitiated) {
                try CoreBridge.snapshot(repositoryPaths: paths)
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
    @State private var pendingPath = ""
    @State private var selectedRepositoryPath: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAEMON").font(.system(size: 25, weight: .light, design: .monospaced)).tracking(3)
                    Text("Scenarys · consola nativa").font(.caption).foregroundStyle(.secondary)
                }
                Rectangle().fill(DaemonPalette.green).frame(width: 26, height: 2)
                Button {
                    selectedRepositoryPath = nil
                } label: {
                    Label("Resumen", systemImage: "square.grid.2x2").font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedRepositoryPath == nil ? DaemonPalette.green : .primary)
                Label("Repositorios · \(model.repositoryPaths.count)", systemImage: "folder").font(.subheadline)
                Label("Evidencia local", systemImage: "checkmark.shield").font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.repositoryPaths, id: \.self) { path in
                            HStack(spacing: 7) {
                                Circle().fill(DaemonPalette.green).frame(width: 5, height: 5)
                                Button {
                                    selectedRepositoryPath = path
                                } label: {
                                    Text(repositoryName(path))
                                        .font(.caption.monospaced()).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectedRepositoryPath == path ? DaemonPalette.green : .primary)
                                Spacer(minLength: 0)
                                Button {
                                    model.removeRepository(path)
                                } label: {
                                    Image(systemName: "xmark").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .help("Quitar del catálogo; no elimina archivos")
                            }
                        }
                    }
                }
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
                    TextField("Ruta de un repositorio Git", text: $pendingPath)
                        .textFieldStyle(.plain).font(.caption.monospaced())
                        .padding(10).background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 7))
                        .onSubmit { addPendingRepository() }
                    Button { choosingDirectory = true } label: { Image(systemName: "folder") }
                        .help("Elegir un repositorio")
                    Button("Añadir") { addPendingRepository() }
                        .disabled(pendingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(model.refreshing ? "Leyendo…" : "Actualizar") { Task { await model.refresh() } }
                        .disabled(model.refreshing).keyboardShortcut("r", modifiers: .command)
                }
                ScrollView {
                    if let snapshot = model.snapshot {
                        if let selectedRepositoryPath,
                           let repository = snapshot.repositories.first(where: {
                               $0.path == selectedRepositoryPath || model.repositoryPaths.first(where: { $0 == selectedRepositoryPath }) == selectedRepositoryPath && repositoryName($0.path) == repositoryName(selectedRepositoryPath)
                           }) {
                            RepositoryWorkspaceView(repository: repository)
                                .frame(minHeight: 590)
                                .padding(.bottom, 20)
                        } else {
                            SnapshotDashboard(snapshot: snapshot).padding(.bottom, 20)
                        }
                    } else if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No verificado").font(.title.weight(.light))
                            Text(error).foregroundStyle(.secondary)
                            Text("El catálogo solo guarda rutas locales; quitar una entrada nunca borra archivos.")
                                .font(.caption).foregroundStyle(.secondary)
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
        .onChange(of: model.repositoryPaths) { _, paths in
            if let selectedRepositoryPath, !paths.contains(selectedRepositoryPath) {
                self.selectedRepositoryPath = nil
            }
        }
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.addRepository(url.path)
                Task { await model.refresh() }
            }
        }
    }

    private func addPendingRepository() {
        model.addRepository(pendingPath)
        pendingPath = ""
        Task { await model.refresh() }
    }

    private func repositoryName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent == "repo"
            ? url.deletingLastPathComponent().lastPathComponent
            : url.lastPathComponent
    }
}
