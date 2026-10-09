import DaemonKit
import Foundation

private enum CheckFailure: Error { case failed(String) }

@main
struct BridgeChecks {
    static func main() throws {
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw CheckFailure.failed(name) }
            print("PASS \(name)")
        }
        let sample = #"{"schemaVersion":1,"timestamp":"2026-10-08T09:00:00Z","mode":"local","repositories":[{"name":"demo","path":"/demo","branch":null,"head":null,"upstream":null,"dirty":null,"ahead":null,"behind":null,"status":"future-state","error":null}],"services":[],"agents":[],"events":[],"nextAction":"Verify the repository."}"#
        let snapshot = try DaemonSnapshot.decode(Data(sample.utf8))
        try check(snapshot.repositories[0].evidence == .unknown, "unknown evidence stays unknown")
        try check(snapshot.repositories[0].workingTreeLabel == "No verificado", "null dirty never becomes clean")
        try check(snapshot.verifiedRepositories == 0, "unknown repo never counts as verified")
        try check(!snapshot.allowsRemoteControl, "local JSON cannot enable remote control")
        let remote = try DaemonSnapshot.decode(Data(sample.replacingOccurrences(of: "\"local\"", with: "\"remote-required\"").utf8))
        try check(!remote.allowsRemoteControl, "imported remote-required snapshot cannot enable control")
        var unsupportedRejected = false
        do {
            _ = try DaemonSnapshot.decode(Data(sample.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8))
        } catch { unsupportedRejected = true }
        try check(unsupportedRejected, "unsupported schema rejected")
        var malformedRejected = false
        do { _ = try DaemonSnapshot.decode(Data("{broken".utf8)) } catch { malformedRejected = true }
        try check(malformedRejected, "malformed JSON rejected")
        var oversizedRejected = false
        do { _ = try DaemonSnapshot.decode(Data(repeating: 32, count: 4 * 1024 * 1024 + 1)) } catch { oversizedRejected = true }
        try check(oversizedRejected, "oversized import rejected")
        try check(CoreBridge.version == "0.2.0", "C ABI version")
        for _ in 0..<20 {
            let value = try CoreBridge.snapshot(repositoryPath: "/daemon-native-test-path-that-does-not-exist")
            guard value.schemaVersion == 1, value.verifiedRepositories == 0, !value.allowsRemoteControl else {
                throw CheckFailure.failed("C ABI allocation, decoding, and free")
            }
        }
        print("PASS C ABI allocation, JSON decoding, and free (20 calls)")
        let repository = try CoreBridge.snapshot(repositoryPath: FileManager.default.currentDirectoryPath)
        try check(repository.mode == "local" && repository.repositories.first?.evidence == .verified,
                  "C ABI reads the explicitly selected build checkout")
        try check(repository.repositories.first?.head != nil && repository.repositories.first?.dirty != nil,
                  "C ABI returns real HEAD and working tree evidence")
        print("ALL DAEMON APPLE BRIDGE CHECKS PASSED")
    }
}
