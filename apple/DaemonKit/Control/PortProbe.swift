import Foundation

public struct ListeningSocket: Codable, Sendable, Hashable, Identifiable {
    public let pid: Int
    public let command: String
    public let address: String
    public let port: UInt16
    public var cpuPercent: Double?
    public var residentBytes: UInt64?
    public var elapsed: String?

    public var id: String { "\(pid)-\(address)-\(port)" }
    public var scope: AddressScope { AddressScope.classify(address) }

    /// Procesos de desarrollo: sus listeners abiertos sí son relevantes.
    public var isDevelopmentProcess: Bool {
        let name = command.lowercased()
        return ["node", "ssh", "neo-cube", "python", "ruby", "java", "deno", "bun", "postgres", "docker", "com.docke", "vite", "expo", "nginx", "httpd", "caddy", "daemon"]
            .contains { name.hasPrefix($0) }
    }

    /// Nombre legible de listeners conocidos del sistema.
    public var knownLabel: String? {
        switch command {
        case "ControlCenter": "Receptor AirPlay (macOS)"
        case "rapportd": "Continuidad (macOS)"
        case "IPNExtension": "Tailscale (extensión de red)"
        case "sharingd": "Compartir (macOS)"
        case "Spotify": "Spotify Connect"
        default: nil
        }
    }
}

public enum PortParser {
    /// Parsea `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` (formato de campos, una
    /// entrada por línea: p=pid, c=comando, n=dirección).
    public static func lsofFields(_ text: String) -> [ListeningSocket] {
        var result: [ListeningSocket] = []
        var pid: Int?
        var command = ""
        for line in text.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int(value); command = ""
            case "c": command = value
            case "n":
                guard let pid, let (address, port) = splitAddress(value) else { continue }
                let socket = ListeningSocket(pid: pid, command: command, address: address, port: port)
                if !result.contains(socket) { result.append(socket) }
            default: continue
            }
        }
        return result.sorted { ($0.port, $0.address) < ($1.port, $1.address) }
    }

    /// "127.0.0.1:8765", "*:5173", "[::1]:3000" → (dirección, puerto).
    public static func splitAddress(_ value: String) -> (String, UInt16)? {
        let name = value.split(separator: " ").first.map(String.init) ?? value
        guard let colon = name.lastIndex(of: ":"), let port = UInt16(name[name.index(after: colon)...]) else { return nil }
        var address = String(name[..<colon])
        if address.hasPrefix("[") && address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        return (address, port)
    }

    /// Parsea `ps -o pid=,%cpu=,rss=,etime= -p …`.
    public static func psStats(_ text: String) -> [Int: (cpu: Double, rssBytes: UInt64, elapsed: String)] {
        var result: [Int: (Double, UInt64, String)] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4, let pid = Int(fields[0]), let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = UInt64(fields[2]) else { continue }
            result[pid] = (cpu, rss * 1024, String(fields[3]))
        }
        return result
    }
}

#if os(macOS)
public enum PortProbe {
    public struct Result: Sendable {
        public let sockets: [ListeningSocket]
        public let evidence: Evidence
        public let provenance: Provenance
        public let error: String?
    }

    public static func listening() async -> Result {
        let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        let started = Date()
        do {
            let output = try await CommandRunner.run("lsof", arguments, timeout: 6)
            var sockets = PortParser.lsofFields(output.standardOutput)
            let pids = Array(Set(sockets.map(\.pid))).sorted()
            if !pids.isEmpty, let ps = try? await CommandRunner.run("ps", ["-o", "pid=,%cpu=,rss=,etime=", "-p", pids.map(String.init).joined(separator: ",")], timeout: 4) {
                let stats = PortParser.psStats(ps.standardOutput)
                for index in sockets.indices {
                    if let stat = stats[sockets[index].pid] {
                        sockets[index].cpuPercent = stat.cpu
                        sockets[index].residentBytes = stat.rssBytes
                        sockets[index].elapsed = stat.elapsed
                    }
                }
            }
            // lsof sale con 1 si no hay coincidencias; sin salida y 1 es "sin listeners".
            let complete = output.exitCode == 0 || (output.exitCode == 1 && output.standardOutput.isEmpty)
            return Result(sockets: sockets, evidence: complete ? (output.truncated ? .partial : .verified) : .partial,
                          provenance: Provenance(source: "lsof + ps", method: "lsof " + arguments.joined(separator: " "), observedAt: started),
                          error: complete ? nil : "lsof terminó con \(output.exitCode)")
        } catch {
            return Result(sockets: [], evidence: .unverified, provenance: Provenance(source: "lsof", method: "no ejecutado", observedAt: started),
                          error: error.localizedDescription)
        }
    }
}
#endif
