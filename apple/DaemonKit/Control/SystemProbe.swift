import Foundation
#if os(macOS)
import Darwin
import IOKit.ps
#endif

public struct NetworkInterface: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let address: String
    public let scope: AddressScope
    public var id: String { name + address }
}

/// Clasificación de una dirección según su superficie de exposición.
public enum AddressScope: String, Codable, Sendable, Comparable {
    case loopback, tailnet, lan, allInterfaces, publicNetwork, unknown

    public var label: String {
        switch self {
        case .loopback: "loopback"
        case .tailnet: "tailnet"
        case .lan: "LAN"
        case .allInterfaces: "todas las interfaces"
        case .publicNetwork: "pública"
        case .unknown: "desconocida"
        }
    }

    var rank: Int {
        switch self { case .loopback: 0; case .tailnet: 1; case .lan: 2; case .unknown: 3; case .allInterfaces: 4; case .publicNetwork: 5 }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    public static func classify(_ rawAddress: String) -> AddressScope {
        let address = rawAddress.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if address == "*" || address == "0.0.0.0" || address == "::" { return .allInterfaces }
        if address == "::1" || address.hasPrefix("127.") || address == "localhost" { return .loopback }
        if address.lowercased().hasPrefix("fd7a:115c:a1e0") { return .tailnet }
        if address.lowercased().hasPrefix("fe80") || address.lowercased().hasPrefix("fd") || address.lowercased().hasPrefix("fc") { return .lan }
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else {
            return address.contains(":") ? .publicNetwork : .unknown
        }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return .tailnet }
        if parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254) { return .lan }
        return .publicNetwork
    }
}

public struct MachineSnapshot: Codable, Sendable {
    public let hostName: String
    public let model: String
    public let osVersion: String
    public let cpuCount: Int
    public let loadAverage: [Double]
    public let memoryTotalBytes: UInt64
    public let memoryUsedBytes: UInt64?
    public let diskTotalBytes: Int64?
    public let diskAvailableBytes: Int64?
    public let uptimeSeconds: TimeInterval
    public let thermalState: String
    public let battery: Battery?
    public let interfaces: [NetworkInterface]
    public let provenance: Provenance

    public struct Battery: Codable, Sendable {
        public let percent: Int
        public let charging: Bool
        public let source: String
    }

    public var memoryPressure: Double? { memoryUsedBytes.map { Double($0) / Double(max(memoryTotalBytes, 1)) } }
    public var cpuLoadRatio: Double { (loadAverage.first ?? 0) / Double(max(cpuCount, 1)) }
}

#if os(macOS)
/// Lecturas del Mac mediante APIs nativas (sysctl, Mach, IOKit, getifaddrs):
/// sin procesos externos.
public enum SystemProbe {
    public static func machine() -> MachineSnapshot {
        let info = ProcessInfo.processInfo
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&loads, 3)
        return MachineSnapshot(
            hostName: Host.current().localizedName ?? info.hostName,
            model: sysctlString("hw.model") ?? "no verificado",
            osVersion: info.operatingSystemVersionString,
            cpuCount: info.activeProcessorCount,
            loadAverage: loadCount > 0 ? Array(loads.prefix(Int(loadCount))) : [],
            memoryTotalBytes: info.physicalMemory,
            memoryUsedBytes: usedMemory(),
            diskTotalBytes: volume(.volumeTotalCapacityKey),
            diskAvailableBytes: volume(.volumeAvailableCapacityForImportantUsageKey),
            uptimeSeconds: info.systemUptime,
            thermalState: thermal(info.thermalState),
            battery: battery(),
            interfaces: interfaces(),
            provenance: Provenance(source: "macOS", method: "sysctl · host_statistics64 · IOKit · getifaddrs")
        )
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return cString(buffer)
    }

    static func cString(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func usedMemory() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        // Activa + cableada + comprimida: lo que Activity Monitor llama "memoria usada".
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func volume(_ key: URLResourceKey) -> Int64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [key])
        switch key {
        case .volumeTotalCapacityKey: return values?.volumeTotalCapacity.map(Int64.init)
        case .volumeAvailableCapacityForImportantUsageKey: return values?.volumeAvailableCapacityForImportantUsage
        default: return nil
        }
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "moderado"
        case .serious: "alto"
        case .critical: "crítico"
        @unknown default: "no verificado"
        }
    }

    static func battery() -> MachineSnapshot.Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return .init(percent: current * 100 / maximum, charging: charging,
                         source: state == kIOPSACPowerValue ? "corriente" : "batería")
        }
        return nil
    }

    public static func interfaces() -> [NetworkInterface] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [NetworkInterface] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr else { continue }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == UInt8(AF_INET) ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var text = cString(host)
            if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
            let name = String(cString: entry.pointee.ifa_name)
            let scope = AddressScope.classify(text)
            // Enlaces locales IPv6 no aportan a la topología.
            if text.lowercased().hasPrefix("fe80") { continue }
            result.append(NetworkInterface(name: name, address: text, scope: scope))
        }
        return result.sorted { ($0.scope, $0.name) < ($1.scope, $1.name) }
    }
}
#endif
