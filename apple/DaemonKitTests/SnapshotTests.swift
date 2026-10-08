import DaemonKit
import Foundation
import XCTest

final class SnapshotTests: XCTestCase {
    private let sample = #"{"schemaVersion":1,"timestamp":"2026-10-08T09:00:00Z","mode":"local","repositories":[{"name":"demo","path":"/demo","branch":null,"head":null,"upstream":null,"dirty":null,"ahead":null,"behind":null,"status":"future-state","error":null}],"services":[],"agents":[],"events":[],"nextAction":"Verify the repository."}"#

    func testUnknownEvidenceNeverBecomesCleanOrVerified() throws {
        let snapshot = try DaemonSnapshot.decode(Data(sample.utf8))
        XCTAssertEqual(snapshot.repositories[0].evidence, .unknown)
        XCTAssertEqual(snapshot.repositories[0].workingTreeLabel, "No verificado")
        XCTAssertEqual(snapshot.verifiedRepositories, 0)
        XCTAssertFalse(snapshot.allowsRemoteControl)
    }

    func testImportedSnapshotCannotEnableControl() throws {
        let input = sample.replacingOccurrences(of: "\"local\"", with: "\"remote-required\"")
        let snapshot = try DaemonSnapshot.decode(Data(input.utf8))
        XCTAssertEqual(snapshot.mode, "remote-required")
        XCTAssertFalse(snapshot.allowsRemoteControl)
    }

    func testUnsupportedSchemaIsRejected() {
        let input = sample.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        XCTAssertThrowsError(try DaemonSnapshot.decode(Data(input.utf8)))
    }

    func testMalformedJSONIsRejected() {
        XCTAssertThrowsError(try DaemonSnapshot.decode(Data("{broken".utf8)))
    }

    func testCABIAllocationAndJSONOwnership() throws {
        XCTAssertEqual(CoreBridge.version, "0.1.0")
        for _ in 0..<20 {
            let snapshot = try CoreBridge.snapshot(repositoryPath: "/daemon-native-test-path-that-does-not-exist")
            XCTAssertEqual(snapshot.schemaVersion, 1)
            XCTAssertEqual(snapshot.verifiedRepositories, 0)
            XCTAssertFalse(snapshot.allowsRemoteControl)
        }
    }
}
