import DaemonNativeCore
import Foundation

public enum CoreBridge {
    public static var version: String { String(cString: daemon_core_version()) }

    public static func snapshot(repositoryPath: String) throws -> DaemonSnapshot {
        try repositoryPath.withCString { path in
            guard let result = daemon_snapshot_json(path) else { throw SnapshotError.allocationFailed }
            defer { daemon_free_string(result) }
            return try DaemonSnapshot.decode(Data(String(cString: result).utf8))
        }
    }
}
