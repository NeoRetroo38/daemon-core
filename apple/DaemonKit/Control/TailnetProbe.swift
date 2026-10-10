import Foundation

public struct TailnetPeer: Codable, Sendable, Hashable, Identifiable {
    public let hostName: String
    public let dnsName: String
    public let os: String
    public let addresses: [String]
    public let online: Bool
    public let active: Bool
    public let lastSeen: Date?
    public let isSelf: Bool
    /// Ida y vuelta medida con `tailscale ping` (nil si no se midió).
    public var latencyMs: Int? = nil

    public var id: String { dnsName.isEmpty ? hostName : dnsName }
    public var ipv4: String? { addresses.first { $0.contains(".") } }
    public var shortName: String { dnsName.split(separator: ".").first.map(String.init) ?? hostName }
}

public struct TailnetSnapshot: Codable, Sendable {
    public let backendState: String
    public let tailnetName: String?
    public let peers: [TailnetPeer]
    public let evidence: Evidence
    public let provenance: Provenance
    public let error: String?

    public var me: TailnetPeer? { peers.first(where: \.isSelf) }
    public var running: Bool { backendState == "Running" }

    public func peer(named name: String) -> TailnetPeer? {
        let wanted = name.lowercased()
        return peers.first { !$0.isSelf && ($0.hostName.lowercased() == wanted || $0.shortName.lowercased() == wanted) }
    }

    public static func unavailable(_ reason: String) -> TailnetSnapshot {
        TailnetSnapshot(backendState: "Unknown", tailnetName: nil, peers: [], evidence: .unverified,
                        provenance: Provenance(source: "tailscale", method: "no ejecutado"), error: reason)
    }
}

public enum TailnetParser {
    /// «pong from desktop (100.x.y.z) via 192.168.1.5:41641 in 3ms» → 3. Acepta decimales («in 12.4ms» → 12).
    public static func pingMilliseconds(_ output: String) -> Int? {
        guard let range = output.range(of: #"in ([0-9]+(\.[0-9]+)?)ms"#, options: .regularExpression) else { return nil }
        let number = output[range].dropFirst(3).dropLast(2)
        return Double(number).map { Int($0.rounded()) }
    }

    /// Parsea `tailscale status --json`. Solo conserva nombre, SO, IPs y
    /// presencia; claves, IDs de nodo y datos de cuenta se descartan.
    public static func status(_ data: Data, observedAt: Date = Date()) -> TailnetSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func peer(_ value: [String: Any], isSelf: Bool) -> TailnetPeer {
            let seen = (value["LastSeen"] as? String).flatMap { iso.date(from: $0) ?? plain.date(from: $0) }
            return TailnetPeer(
                hostName: value["HostName"] as? String ?? "?",
                dnsName: (value["DNSName"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                os: value["OS"] as? String ?? "?",
                addresses: value["TailscaleIPs"] as? [String] ?? [],
                online: value["Online"] as? Bool ?? false,
                active: value["Active"] as? Bool ?? false,
                lastSeen: seen.flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil },
                isSelf: isSelf
            )
        }
        var peers: [TailnetPeer] = []
        if let me = root["Self"] as? [String: Any] { peers.append(peer(me, isSelf: true)) }
        if let others = root["Peer"] as? [String: [String: Any]] {
            peers += others.values.map { peer($0, isSelf: false) }.sorted { $0.hostName.lowercased() < $1.hostName.lowercased() }
        }
        let tailnet = (root["CurrentTailnet"] as? [String: Any])?["Name"] as? String
        let state = root["BackendState"] as? String ?? "Unknown"
        return TailnetSnapshot(backendState: state, tailnetName: tailnet, peers: peers,
                               evidence: state == "Running" ? .verified : .partial,
                               provenance: Provenance(source: "Tailscale", method: "tailscale status --json", observedAt: observedAt),
                               error: nil)
    }
}

#if os(macOS)
public enum TailnetProbe {
    /// Un ping por nodo en línea, en paralelo y con tope de 2 s: da los ms reales de cada enlace de la tailnet.
    static func withPings(_ snapshot: TailnetSnapshot) async -> TailnetSnapshot {
        let peers = await withTaskGroup(of: (Int, Int?).self) { group in
            for (index, peer) in snapshot.peers.enumerated() where !peer.isSelf && peer.online {
                guard let ip = peer.ipv4 else { continue }
                group.addTask {
                    let result = try? await CommandRunner.run("tailscale", ["ping", "-c", "1", "--timeout", "2s", ip], timeout: 4)
                    return (index, result.flatMap { TailnetParser.pingMilliseconds($0.standardOutput) })
                }
            }
            var measured = snapshot.peers
            for await (index, ms) in group { measured[index].latencyMs = ms }
            return measured
        }
        return TailnetSnapshot(backendState: snapshot.backendState, tailnetName: snapshot.tailnetName, peers: peers,
                               evidence: snapshot.evidence, provenance: snapshot.provenance, error: snapshot.error)
    }

    public static func status() async -> TailnetSnapshot {
        do {
            let result = try await CommandRunner.run("tailscale", ["status", "--json"], timeout: 6)
            guard let snapshot = TailnetParser.status(Data(result.standardOutput.utf8)) else {
                return .unavailable(result.succeeded ? "Respuesta de Tailscale no reconocida" : "Tailscale no responde (código \(result.exitCode))")
            }
            return await withPings(snapshot)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}
#endif
