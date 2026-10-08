import DaemonKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct DaemonIOSDashboard: View {
    @State private var snapshot: DaemonSnapshot?
    @State private var error: String?
    @State private var importing = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("DAEMON").font(.system(size: 24, weight: .light, design: .monospaced)).tracking(3)
                        Spacer()
                        EvidenceBadge(.unknown)
                    }
                    Text("iPhone · lectura de instantáneas").font(.subheadline).foregroundStyle(.secondary)
                    Button("Importar instantánea JSON") { importing = true }
                        .buttonStyle(.bordered).tint(DaemonPalette.green)
                    if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    if let snapshot {
                        SnapshotDashboard(snapshot: snapshot, imported: true)
                    } else {
                        Text("Importa un archivo exportado por el núcleo del Mac. Sin ese archivo, repositorios y servicios siguen sin verificar.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conexión con el Mac").font(.headline.weight(.regular))
                        Text("API segura no configurada. El iPhone no ejecuta comandos ni consulta repositorios locales del Mac.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Control remoto no disponible") {}.disabled(true)
                    }
                    Text("CORE \(CoreBridge.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }.padding(22)
            }
            .background(DaemonPalette.background)
            .navigationTitle("Scenarys")
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let size = attributes[.size] as? NSNumber, size.intValue > 4 * 1024 * 1024 {
                    throw SnapshotError.tooLarge
                }
                snapshot = try DaemonSnapshot.decode(Data(contentsOf: url))
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
