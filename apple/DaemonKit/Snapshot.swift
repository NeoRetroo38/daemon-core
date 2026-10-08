import Foundation

public enum EvidenceState: String, Sendable {
    case verified, unavailable, unknown

    public var label: String {
        switch self {
        case .verified: "Verificado"
        case .unavailable: "No disponible"
        case .unknown: "No verificado"
        }
    }
}

public struct RepositorySnapshot: Codable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let branch: String?
    public let head: String?
    public let upstream: String?
    public let dirty: Bool?
    public let ahead: Int?
    public let behind: Int?
    public let status: String
    public let error: String?

    public var id: String { path }
    public var evidence: EvidenceState {
        switch status {
        case "ready": .verified
        case "unavailable": .unavailable
        default: .unknown
        }
    }
    public var workingTreeLabel: String {
        switch dirty {
        case true: "Cambios locales"
        case false: "Limpio"
        case nil: "No verificado"
        }
    }
    public var comparisonLabel: String {
        guard let ahead, let behind else { return "Remoto: no verificado" }
        return "\(ahead) por delante · \(behind) por detrás"
    }
}

// Reserved sections remain evidence-only. Empty arrays do not mean healthy services.
public struct SnapshotEvidence: Codable, Sendable {
    public let name: String?
    public let status: String?
    public let message: String?
}

public struct TraceEventSnapshot: Codable, Sendable {
    public let timestamp: String
    public let actor: String
    public let machine: String
    public let repository: String
    public let branch: String
    public let commit: String
    public let operation: String
    public let result: String
    public let durationMs: UInt64
}

public struct DaemonSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let timestamp: String?
    public let mode: String
    public let repositories: [RepositorySnapshot]
    public let services: [SnapshotEvidence]
    public let agents: [SnapshotEvidence]
    public let events: [TraceEventSnapshot]
    public let nextAction: String

    public var verifiedRepositories: Int { repositories.filter { $0.evidence == .verified }.count }
    public var allowsRemoteControl: Bool { false }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4 * 1024 * 1024 else { throw SnapshotError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw SnapshotError.unsupportedSchema(value.schemaVersion) }
        guard ["local", "remote-required", "unavailable"].contains(value.mode) else { throw SnapshotError.unsupportedMode }
        return value
    }
}

public enum SnapshotError: Error, LocalizedError {
    case allocationFailed
    case tooLarge
    case unsupportedSchema(Int)
    case unsupportedMode

    public var errorDescription: String? {
        switch self {
        case .allocationFailed: "El núcleo no pudo crear la instantánea."
        case .tooLarge: "La instantánea supera el límite de 4 MB."
        case .unsupportedSchema(let version): "Formato de instantánea no compatible: \(version)."
        case .unsupportedMode: "La instantánea declara un modo no compatible."
        }
    }
}
