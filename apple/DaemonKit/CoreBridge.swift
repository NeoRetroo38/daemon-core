import DaemonNativeCore
import Foundation

public enum CoreBridge {
    public static var version: String { String(cString: daemon_core_version()) }

    public static func snapshot(repositoryPath: String) throws -> DaemonSnapshot {
        try snapshot(repositoryPaths: [repositoryPath])
    }

    public static func snapshot(repositoryPaths: [String]) throws -> DaemonSnapshot {
        var pointers: [UnsafePointer<CChar>?] = []

        func callCore() throws -> DaemonSnapshot {
            try pointers.withUnsafeBufferPointer { buffer in
                guard let result = daemon_snapshot_json_many(buffer.baseAddress, buffer.count) else {
                    throw SnapshotError.allocationFailed
                }
                defer { daemon_free_string(result) }
                return try DaemonSnapshot.decode(Data(String(cString: result).utf8))
            }
        }

        func appendCString(at index: Int) throws -> DaemonSnapshot {
            guard repositoryPaths.indices.contains(index) else { return try callCore() }
            return try repositoryPaths[index].withCString { pointer in
                pointers.append(pointer)
                defer { pointers.removeLast() }
                return try appendCString(at: index + 1)
            }
        }

        return try appendCString(at: 0)
    }
}

public struct ExposureVerdict: Codable, Sendable, Equatable {
    public let status: String
    public let reason: String
    public var exposed: Bool { status == "EXPOSED" }
    public var safe: Bool { status == "SAFE" }
}

extension CoreBridge {
    /// Pregunta al gate C++ qué clase de comando es y si puede ejecutarse.
    public static func evaluatePolicy(executable: String, arguments: [String], allowWrite: Bool, allowNetwork: Bool) -> PolicyDecision {
        let fallback = PolicyDecision(verdict: .deny, classification: "PRIVILEGED", reason: "POLICY_UNAVAILABLE")
        let json: String? = withCStrings(arguments) { pointers in
            executable.withCString { exe in
                pointers.withUnsafeBufferPointer { buffer in
                    guard let raw = daemon_policy_evaluate(exe, buffer.baseAddress, buffer.count, allowWrite ? 1 : 0, allowNetwork ? 1 : 0) else { return nil }
                    defer { daemon_free_string(raw) }
                    return String(cString: raw)
                }
            }
        }
        guard let json, let value = try? JSONDecoder().decode(PolicyDecision.self, from: Data(json.utf8)) else { return fallback }
        return value
    }

    /// Comprueba bindings observados contra el contrato del Cubo (127.0.0.1:8765).
    public static func checkExposure(_ bindings: [(address: String, port: UInt16)], complete: Bool) -> ExposureVerdict {
        let ports = bindings.map { UInt16($0.port) }
        let json: String? = withCStrings(bindings.map(\.address)) { pointers in
            ports.withUnsafeBufferPointer { portBuffer in
                pointers.withUnsafeBufferPointer { buffer in
                    guard let raw = daemon_check_exposure(buffer.baseAddress, portBuffer.baseAddress, buffer.count, complete ? 1 : 0) else { return nil }
                    defer { daemon_free_string(raw) }
                    return String(cString: raw)
                }
            }
        }
        guard let json, let value = try? JSONDecoder().decode(ExposureVerdict.self, from: Data(json.utf8)) else {
            return ExposureVerdict(status: "UNKNOWN", reason: "EXPOSURE_CHECK_UNAVAILABLE")
        }
        return value
    }

    /// Redacción defensiva de credenciales antes de mostrar texto operativo.
    public static func redact(_ text: String) -> String {
        text.withCString { pointer in
            guard let raw = daemon_redact(pointer) else { return "[redactado]" }
            defer { daemon_free_string(raw) }
            return String(cString: raw)
        }
    }

    /// Mantiene vivas las cadenas C durante la llamada sin copiar a mano.
    static func withCStrings<R>(_ strings: [String], _ body: ([UnsafePointer<CChar>?]) -> R) -> R {
        let duplicated = strings.map { strdup($0) }
        defer { duplicated.forEach { free($0) } }
        return body(duplicated.map { UnsafePointer($0) })
    }
}
