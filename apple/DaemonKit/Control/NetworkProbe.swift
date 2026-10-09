import Foundation
import Network

public struct ProbeResult: Codable, Sendable, Hashable {
    public let target: String
    public let reachable: Bool
    public let statusCode: Int?
    public let latencyMs: Int?
    public let evidence: Evidence
    public let detail: String
    public let provenance: Provenance

    public var summary: String {
        guard reachable else { return detail }
        let code = statusCode.map { "HTTP \($0)" } ?? "TCP abierto"
        return "\(code) · \(latencyMs.map { "\($0) ms" } ?? "—")"
    }
}

/// Sondas de red sin cuerpos ni credenciales: no se envían cookies, no se
/// guarda caché y solo se conserva el código de estado y la latencia.
public enum NetworkProbe {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public static func http(_ url: URL, timeout: TimeInterval = 3, method: String = "GET") async -> ProbeResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        let started = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return ProbeResult(target: url.absoluteString, reachable: true, statusCode: nil, latencyMs: elapsed, evidence: .partial,
                                   detail: "respuesta no HTTP", provenance: Provenance(source: url.host ?? "?", method: "\(method) \(url.path)", observedAt: started))
            }
            let code = http.statusCode
            // 401/403 demuestran que el servicio vive y exige autenticación.
            let evidence: Evidence = (200..<400).contains(code) || code == 401 || code == 403 ? .verified : (code >= 500 ? .failed : .partial)
            let detail = code == 401 || code == 403 ? "vivo · exige autenticación" : (code < 400 ? "responde" : "responde con error")
            return ProbeResult(target: url.absoluteString, reachable: true, statusCode: code, latencyMs: elapsed, evidence: evidence,
                               detail: detail, provenance: Provenance(source: url.host ?? "?", method: "\(method) \(url.path.isEmpty ? "/" : url.path)", observedAt: started))
        } catch {
            let nsError = error as NSError
            let reason: String
            switch nsError.code {
            case NSURLErrorTimedOut: reason = "sin respuesta en \(Int(timeout)) s"
            case NSURLErrorCannotConnectToHost: reason = "conexión rechazada"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: reason = "host no resuelto"
            case NSURLErrorNotConnectedToInternet: reason = "sin red"
            default: reason = "no alcanzable"
            }
            return ProbeResult(target: url.absoluteString, reachable: false, statusCode: nil, latencyMs: nil, evidence: .failed,
                               detail: reason, provenance: Provenance(source: url.host ?? "?", method: "\(method) \(url.path)", observedAt: started))
        }
    }

    /// Apertura TCP sin enviar datos: sirve para detectar exposición del Cubo.
    public static func tcp(host: String, port: UInt16, timeout: TimeInterval = 2) async -> ProbeResult {
        let started = Date()
        let target = "\(host):\(port)"
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return ProbeResult(target: target, reachable: false, statusCode: nil, latencyMs: nil, evidence: .failed, detail: "puerto inválido",
                               provenance: Provenance(source: host, method: "TCP connect", observedAt: started))
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = OnceGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if gate.claim() { continuation.resume(returning: true) }
                case .failed, .cancelled: if gate.claim() { continuation.resume(returning: false) }
                case .waiting: if gate.claim() { continuation.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { continuation.resume(returning: false) }
            }
        }
        connection.cancel()
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return ProbeResult(target: target, reachable: outcome, statusCode: nil, latencyMs: outcome ? elapsed : nil,
                           evidence: outcome ? .verified : .failed, detail: outcome ? "TCP abierto" : "TCP cerrado o filtrado",
                           provenance: Provenance(source: host, method: "TCP connect :\(port)", observedAt: started))
    }
}

final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

/// Historial de latencias en memoria para p50/p95/p99 por servicio.
public actor LatencyHistory {
    public static let shared = LatencyHistory()
    private var samples: [String: [Int]] = [:]
    private var outcomes: [String: (ok: Int, fail: Int, lastOK: Date?)] = [:]

    public func record(_ key: String, _ result: ProbeResult) {
        var current = outcomes[key] ?? (0, 0, nil)
        if result.reachable, let latency = result.latencyMs {
            samples[key, default: []].append(latency)
            if samples[key]!.count > 240 { samples[key]!.removeFirst(samples[key]!.count - 240) }
            current.ok += 1
            current.lastOK = result.provenance.observedAt
        } else {
            current.fail += 1
        }
        outcomes[key] = current
    }

    public func stats(_ key: String) -> LatencyStats {
        let values = (samples[key] ?? []).sorted()
        func percentile(_ p: Double) -> Int? {
            guard !values.isEmpty else { return nil }
            return values[min(values.count - 1, Int((Double(values.count - 1) * p).rounded()))]
        }
        let outcome = outcomes[key]
        return LatencyStats(samples: values.count, p50: percentile(0.5), p95: percentile(0.95), p99: percentile(0.99),
                            successes: outcome?.ok ?? 0, failures: outcome?.fail ?? 0, lastHealthy: outcome?.lastOK)
    }
}

public struct LatencyStats: Codable, Sendable, Hashable {
    public let samples: Int
    public let p50: Int?
    public let p95: Int?
    public let p99: Int?
    public let successes: Int
    public let failures: Int
    public let lastHealthy: Date?

    public static let empty = LatencyStats(samples: 0, p50: nil, p95: nil, p99: nil, successes: 0, failures: 0, lastHealthy: nil)
}
