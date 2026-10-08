import SwiftUI

public enum DaemonPalette {
    public static let background = Color.black
    public static let panel = Color(white: 0.065)
    public static let line = Color(white: 0.17)
    public static let green = Color(red: 57 / 255, green: 1, blue: 20 / 255)
}

public struct EvidenceBadge: View {
    public let state: EvidenceState

    public init(_ state: EvidenceState) { self.state = state }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state == .verified ? DaemonPalette.green : Color.gray).frame(width: 6, height: 6)
            Text(state.label).font(.caption)
        }
        .foregroundStyle(state == .verified ? DaemonPalette.green : .secondary)
    }
}

public struct SnapshotDashboard: View {
    public let snapshot: DaemonSnapshot
    public let imported: Bool

    public init(snapshot: DaemonSnapshot, imported: Bool = false) {
        self.snapshot = snapshot
        self.imported = imported
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("Estado operativo").font(.system(size: 30, weight: .light))
                Spacer()
                Text("\(snapshot.verifiedRepositories) verificados").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(imported ? "Instantánea importada · lectura" : (snapshot.mode == "local" ? "Evidencia local · lectura de Git" : "Lectura local no disponible"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(snapshot.timestamp ?? "Timestamp no disponible").font(.caption.monospaced()).foregroundStyle(.secondary)
                if imported {
                    Text("Describe el momento del archivo; no confirma el estado actual del Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(snapshot.repositories) { repository in
                RepositoryCard(repository: repository)
            }
            if snapshot.repositories.isEmpty {
                evidencePanel(title: "Repositorios", message: "No hay evidencia en esta instantánea.")
            }
            evidencePanel(title: "Servicios", message: "No verificado · esta lectura no comprueba API, VPN ni motor.")
            evidencePanel(title: "Agentes", message: "No verificado · ningún agente se descubre por suposición.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Siguiente acción").font(.caption).foregroundStyle(DaemonPalette.green)
                Text(snapshot.nextAction).font(.body).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DaemonPalette.line))
        }
    }

    private func evidencePanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline.weight(.regular))
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}

public struct RepositoryCard: View {
    public let repository: RepositorySnapshot

    public init(repository: RepositorySnapshot) { self.repository = repository }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(repository.name).font(.system(size: 21, weight: .light))
                Spacer()
                EvidenceBadge(repository.evidence)
            }
            Text(repository.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Divider().overlay(DaemonPalette.line)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                detailRow("Rama", repository.branch ?? "No verificado")
                detailRow("HEAD", repository.head ?? "No verificado")
                detailRow("Archivos", repository.workingTreeLabel)
                detailRow("Seguimiento", repository.upstream ?? "No configurado o no verificado")
            }
            Text(repository.comparisonLabel).font(.caption).foregroundStyle(.secondary)
            if let error = repository.error, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DaemonPalette.line))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
        }
        .font(.subheadline)
    }
}
