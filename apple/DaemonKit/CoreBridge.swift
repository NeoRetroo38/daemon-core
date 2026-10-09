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
