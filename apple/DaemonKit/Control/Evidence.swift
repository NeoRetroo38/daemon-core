import Foundation

/// Calidad de una observación. Nunca se eleva un estado por inferencia:
/// lo no medido es `unverified`, lo medido a medias es `partial`.
public enum Evidence: String, Codable, Sendable, CaseIterable {
    case verified, partial, unverified, failed

    public var label: String {
        switch self {
        case .verified: "verificado"
        case .partial: "parcial"
        case .unverified: "no verificado"
        case .failed: "fallo"
        }
    }

    /// Combina evidencias: el conjunto vale lo que su eslabón más débil.
    public static func weakest(_ values: [Evidence]) -> Evidence {
        guard !values.isEmpty else { return .unverified }
        if values.contains(.failed) { return .failed }
        if values.contains(.unverified) { return values.contains(.verified) ? .partial : .unverified }
        if values.contains(.partial) { return .partial }
        return .verified
    }
}

/// Procedencia de cualquier valor que Daemon muestra: de dónde sale, cómo se
/// midió y cuándo.
public struct Provenance: Codable, Sendable, Hashable {
    public let source: String
    public let method: String
    public let observedAt: Date

    public init(source: String, method: String, observedAt: Date = Date()) {
        self.source = source
        self.method = method
        self.observedAt = observedAt
    }
}

public struct Metric: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let value: Double?
    public let display: String
    public let evidence: Evidence
    public let provenance: Provenance

    public init(id: String, label: String, value: Double?, display: String? = nil, evidence: Evidence? = nil, provenance: Provenance) {
        self.id = id
        self.label = label
        self.value = value
        self.display = display ?? value.map { Metric.format($0) } ?? "no verificado"
        self.evidence = evidence ?? (value == nil ? .unverified : .verified)
        self.provenance = provenance
    }

    public static func format(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e12 ? String(Int64(value)) : String(format: "%.1f", value)
    }
}

public enum DaemonClock {
    public static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "ahora" }
        if seconds < 60 { return "hace \(seconds) s" }
        if seconds < 3600 { return "hace \(seconds / 60) min" }
        if seconds < 86_400 { return "hace \(seconds / 3600) h" }
        return "hace \(seconds / 86_400) d"
    }
}

/// Veredicto del gate C++ (`daemon_policy_evaluate`). Swift nunca decide por
/// su cuenta si un comando es de lectura: lo pregunta al núcleo.
public struct PolicyDecision: Codable, Sendable, Equatable {
    public enum Verdict: String, Codable, Sendable { case allow, approval, deny }
    public let verdict: Verdict
    public let classification: String
    public let reason: String
}

