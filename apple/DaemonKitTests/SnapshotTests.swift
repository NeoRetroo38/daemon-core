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

    func testMultipleRepositorySnapshotUsesOneEnvelope() throws {
        let snapshot = try CoreBridge.snapshot(repositoryPaths: [
            "/daemon-native-test-path-one-that-does-not-exist",
            "/daemon-native-test-path-two-that-does-not-exist",
        ])
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.repositories.count, 2)
        XCTAssertEqual(snapshot.repositories.map(\.evidence), [.unavailable, .unavailable])
        XCTAssertFalse(snapshot.allowsRemoteControl)
    }

    func testEmptyRepositoryCatalogIsValid() throws {
        let snapshot = try CoreBridge.snapshot(repositoryPaths: [])
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertTrue(snapshot.repositories.isEmpty)
        XCTAssertFalse(snapshot.allowsRemoteControl)
    }

    func testRepositoryInspectorFindsLocalCapabilitiesWithoutWriting() throws {
        let insights = RepositoryInspector.inspect(path: FileManager.default.currentDirectoryPath)
        XCTAssertGreaterThan(insights.fileCount, 0)
        XCTAssertGreaterThan(insights.sourceLines, 0)
        XCTAssertTrue(insights.capabilities.contains("Swift nativo"))
        XCTAssertTrue(insights.capabilities.contains("C++ / Cubo"))
    }

    func testFilesystemDiagnosticOnlyReportsExistingEvidence() async {
        let diagnostic = RepositoryDiagnostic(
            id: "fixture", title: "Fixture", detail: "Read only",
            kind: .files([FileManager.default.currentDirectoryPath + "/Package.swift"])
        )
        let state = await DiagnosticCatalog.run(diagnostic)
        guard case .passed = state else { return XCTFail("Expected existing read-only evidence") }
    }

    func testIdentityProjectionReturnsOnlyDisplayNames() {
        let fixture = #"{"version":1,"accounts":[{"id":"private-id","email":"private@example.test","passwordHash":"secret","profile":{"id":"profile-id","displayName":"Neo","role":"SUPERDEV"}}],"sessions":[{"tokenHash":"secret-token"}]}"#
        XCTAssertEqual(RepositoryInspector.usernames(from: Data(fixture.utf8)), ["Neo"])
    }
}
