import DaemonKit
import Foundation
import XCTest

final class ControlPlaneTests: XCTestCase {
    func testEvidenceNeverUpgradesByInference() {
        XCTAssertEqual(Evidence.weakest([]), .unverified)
        XCTAssertEqual(Evidence.weakest([.verified, .verified]), .verified)
        XCTAssertEqual(Evidence.weakest([.verified, .unverified]), .partial)
        XCTAssertEqual(Evidence.weakest([.unverified, .unverified]), .unverified)
        XCTAssertEqual(Evidence.weakest([.verified, .failed]), .failed)
        XCTAssertEqual(Metric(id: "x", label: "x", value: nil, provenance: Provenance(source: "t", method: "t")).evidence, .unverified)
    }

    func testAddressScopes() {
        XCTAssertEqual(AddressScope.classify("127.0.0.1"), .loopback)
        XCTAssertEqual(AddressScope.classify("::1"), .loopback)
        XCTAssertEqual(AddressScope.classify("*"), .allInterfaces)
        XCTAssertEqual(AddressScope.classify("0.0.0.0"), .allInterfaces)
        XCTAssertEqual(AddressScope.classify("100.101.102.103"), .tailnet)
        XCTAssertEqual(AddressScope.classify("fd7a:115c:a1e0::1"), .tailnet)
        XCTAssertEqual(AddressScope.classify("192.168.1.20"), .lan)
        XCTAssertEqual(AddressScope.classify("203.0.113.9"), .publicNetwork)
        XCTAssertTrue(AddressScope.allInterfaces > AddressScope.tailnet)
    }

    func testLsofFieldParsing() {
        let output = "p812\ncnode\nn127.0.0.1:3000\nn[::1]:3000\np900\ncneo-cube-service\nn127.0.0.1:8765\np901\ncControlCenter\nn*:5000\n"
        let sockets = PortParser.lsofFields(output)
        XCTAssertEqual(sockets.count, 4)
        XCTAssertEqual(sockets.first { $0.port == 8765 }?.command, "neo-cube-service")
        XCTAssertEqual(sockets.first { $0.address == "::1" }?.scope, .loopback)
        XCTAssertEqual(sockets.first { $0.port == 5000 }?.scope, .allInterfaces)
        XCTAssertFalse(sockets.first { $0.port == 5000 }!.isDevelopmentProcess)
        XCTAssertTrue(sockets.first { $0.port == 3000 }!.isDevelopmentProcess)
        let stats = PortParser.psStats("  812  1,5  20480 01:02:03\n900 0.0 1024 05:00\n")
        XCTAssertEqual(stats[812]?.cpu, 1.5)
        XCTAssertEqual(stats[812]?.rssBytes, 20480 * 1024)
        XCTAssertEqual(stats[900]?.elapsed, "05:00")
    }

    func testCubeExposureThroughCore() {
        XCTAssertTrue(CoreBridge.checkExposure([(address: "127.0.0.1", port: 8765)], complete: true).safe)
        XCTAssertTrue(CoreBridge.checkExposure([(address: "*", port: 8765)], complete: true).exposed)
        XCTAssertTrue(CoreBridge.checkExposure([(address: "100.64.0.3", port: 8765)], complete: false).exposed)
        XCTAssertEqual(CoreBridge.checkExposure([], complete: false).status, "UNKNOWN")
    }

    func testPolicyGateIsTheCore() {
        XCTAssertEqual(CoreBridge.evaluatePolicy(executable: "/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], allowWrite: false, allowNetwork: false).verdict, .allow)
        XCTAssertEqual(CoreBridge.evaluatePolicy(executable: "/usr/bin/git", arguments: ["push", "--force"], allowWrite: true, allowNetwork: true).verdict, .deny)
        XCTAssertEqual(CoreBridge.evaluatePolicy(executable: "/usr/bin/ssh", arguments: ["-N", "-L", "0.0.0.0:8765:127.0.0.1:8765", "desktop"], allowWrite: true, allowNetwork: true).verdict, .deny)
        XCTAssertEqual(CoreBridge.evaluatePolicy(executable: "/usr/bin/ssh", arguments: ["-N", "-L", "127.0.0.1:8765:127.0.0.1:8765", "u@desktop"], allowWrite: false, allowNetwork: false).verdict, .approval)
        XCTAssertEqual(CoreBridge.evaluatePolicy(executable: "/bin/bash", arguments: ["-c", "echo"], allowWrite: true, allowNetwork: true).verdict, .deny)
        XCTAssertFalse(CoreBridge.redact("DATABASE_URL=postgresql://u:synthetic-secret@h/db").contains("synthetic-secret"))
    }

    func testCommandRunnerRefusesWithoutApproval() async {
        do {
            _ = try await CommandRunner.run("/usr/bin/git", ["commit", "-m", "x"], approval: .automatic)
            XCTFail("A write must not run automatically")
        } catch CommandError.needsApproval(let decision) {
            XCTAssertEqual(decision.classification, "WRITE")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        do {
            _ = try await CommandRunner.run("/usr/bin/git", ["push", "--force"], approval: .userConfirmed)
            XCTFail("Force push must never run")
        } catch CommandError.denied {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testTailnetParsingDropsKeys() throws {
        let json = #"{"BackendState":"Running","CurrentTailnet":{"Name":"neo.github"},"Self":{"HostName":"MacBook","DNSName":"macbook.tail.ts.net.","OS":"macOS","TailscaleIPs":["100.1.2.3","fd7a:115c:a1e0::3"],"Online":true,"PublicKey":"nodekey:secret"},"Peer":{"nodekey:abc":{"HostName":"DESKTOP-DGJSRGV","DNSName":"desktop-dgjsrgv.tail.ts.net.","OS":"windows","TailscaleIPs":["100.4.5.6"],"Online":true,"LastSeen":"2026-10-09T10:00:00Z"},"nodekey:def":{"HostName":"iPhone","DNSName":"iphone.tail.ts.net.","OS":"iOS","TailscaleIPs":["100.7.8.9"],"Online":false}}}"#
        let snapshot = try XCTUnwrap(TailnetParser.status(Data(json.utf8)))
        XCTAssertTrue(snapshot.running)
        XCTAssertEqual(snapshot.tailnetName, "neo.github")
        XCTAssertEqual(snapshot.me?.ipv4, "100.1.2.3")
        XCTAssertEqual(snapshot.peer(named: "desktop-dgjsrgv")?.ipv4, "100.4.5.6")
        XCTAssertNil(snapshot.peer(named: "macbook"), "self is not a peer")
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("nodekey"))
        XCTAssertNil(TailnetParser.status(Data("The Tailscale GUI failed to start".utf8)))
    }

    func testGitParsers() {
        let log = "0123456789abcdef0123456789abcdef01234567\u{1f}1791500000\u{1f}Juan\u{1f}feat: cubo\n"
        let commits = GitParser.log(log)
        XCTAssertEqual(commits.first?.shortHash, "0123456")
        XCTAssertEqual(commits.first?.subject, "feat: cubo")
        let changes = GitParser.numstat("10\t2\tapple/A.swift\n-\t-\tasset.png\n")
        XCTAssertEqual(changes.count, 2)
        XCTAssertNil(changes[1].added)
        XCTAssertEqual(GitParser.githubSlug("https://github.com/NeoRetroo38/choisys.git"), "NeoRetroo38/choisys")
        XCTAssertEqual(GitParser.githubSlug("git@github.com:NeoRetroo38/daemon-core.git"), "NeoRetroo38/daemon-core")
        XCTAssertEqual(GitParser.githubSlug("https://user:token@github.com/NeoRetroo38/u"), "NeoRetroo38/u")
        XCTAssertNil(GitParser.githubSlug("https://gitlab.com/x/y.git"))
    }

    func testNeonProjectionKeepsOnlyBooleansAndCodes() {
        let output = "> choisys check\n{\"configured\":true,\"urlValid\":true,\"ok\":false,\"connected\":true,\"tables\":true,\"migrations\":false,\"errorCode\":\"P1001\",\"host\":\"secret.neon.tech\"}\n"
        let report = NeonReport.parse(output, durationMs: 1200)
        XCTAssertEqual(report.ok, false)
        XCTAssertEqual(report.flags["connected"], true)
        XCTAssertEqual(report.flags["migrations"], false)
        XCTAssertNil(report.flags["host"])
        XCTAssertEqual(report.errorCode, "P1001")
        XCTAssertEqual(report.evidence, .partial)
        XCTAssertEqual(NeonReport.parse("{\"ok\":false,\"errorCode\":\"postgresql://u:p@h\"}", durationMs: 1).errorCode, nil)
        XCTAssertEqual(NeonReport.parse("nothing", durationMs: 1).evidence, .unverified)
    }

    func testVersionAndBrewParsing() {
        XCTAssertEqual(VersionParser.first("gh version 2.81.0 (2026-09-01)"), "2.81.0")
        XCTAssertEqual(VersionParser.first("OpenSSH_9.9p2, LibreSSL 3.3.6"), "9.9")
        let brew = #"{"formulae":[{"name":"gh","license":"MIT","installed":[{"version":"2.81.0"}]}],"casks":[]}"#
        XCTAssertEqual(VersionParser.brewFormulae(Data(brew.utf8))["gh"]?.license, "MIT")
    }

    func testIntentRouterUsesRealToolsForNeoQuestions() {
        let repos = ["choisys", "daemon-core", "cubo-de-neo", "scenarys", "neo-cube-web"]
        func tool(_ text: String) -> String? { IntentRouter.route(text, repositories: repos)?.tool }
        XCTAssertEqual(tool("¿Cómo está choisys?"), "choisys.health")
        XCTAssertEqual(tool("¿Qué repos tienen cambios?"), "repo.list")
        XCTAssertEqual(IntentRouter.route("¿Qué puerto usa la API?", repositories: repos)?.arguments["port"], "3000")
        XCTAssertEqual(tool("¿Está vivo el Cubo del Desktop?"), "cube.health")
        XCTAssertEqual(tool("¿Qué latencia tengo con Neon?"), "neon.health")
        XCTAssertEqual(tool("¿Qué PRs están abiertas?"), "github.prs")
        XCTAssertEqual(tool("¿Qué ha cambiado hoy?"), "repo.timeline")
        XCTAssertEqual(IntentRouter.route("¿Qué proceso está usando 8081?", repositories: repos)?.arguments["port"], "8081")
        XCTAssertEqual(tool("¿Cuál es la ruta completa frontend → API → Cubo?"), "choisys.health")
        let tests = IntentRouter.route("Ejecuta los tests de daemon-core.", repositories: repos)
        XCTAssertEqual(tests?.tool, "repo.tests")
        XCTAssertEqual(tests?.arguments["repo"], "daemon-core")
        XCTAssertEqual(tests?.explicitCommand, true)
        XCTAssertEqual(tool("Abre el repo de choisys."), "repo.open")
        XCTAssertEqual(tool("Muéstrame el diff."), "repo.diff")
        XCTAssertEqual(tool("Comprueba la tailnet."), "network.tailnet")
        XCTAssertEqual(tool("Compila Daemon."), "daemon.build")
        XCTAssertEqual(tool("Instala esta versión."), "daemon.install")
        XCTAssertEqual(tool("abre el túnel del cubo"), "cube.tunnel.open")
        XCTAssertEqual(tool("cierra el túnel"), "cube.tunnel.close")
        XCTAssertNotEqual(tool("ejecuta las pruebas de prisma"), "github.prs")
        XCTAssertNil(tool("cuéntame un chiste"))
    }

    func testToolCatalogDeclaresRiskAndNoShell() {
        XCTAssertEqual(Set(ToolCatalog.all.map(\.name)).count, ToolCatalog.all.count, "unique tool names")
        XCTAssertFalse(ToolCatalog.all.contains { $0.name.contains("shell") || $0.name.contains("exec") })
        XCTAssertEqual(ToolCatalog.spec("daemon.install")?.requiresConfirmation, true)
        XCTAssertEqual(ToolCatalog.spec("service.stop")?.requiresConfirmation, true)
        XCTAssertEqual(ToolCatalog.spec("system.ports")?.risk, .read)
        XCTAssertEqual(ToolCatalog.spec("cube.tunnel.open")?.risk, .network)
    }

    func testCubeLevelsAndShape() {
        XCTAssertEqual(CubeModel.level(nil, 1, 10), 1)
        XCTAssertEqual(CubeModel.level(0, 1, 10), 1)
        XCTAssertEqual(CubeModel.level(5, 1, 10), 2)
        XCTAssertEqual(CubeModel.level(10, 1, 10), 3)
        let repository = try! JSONDecoder().decode(RepositorySnapshot.self, from: Data(#"{"name":"demo","path":"/demo","branch":"main","head":"abc","upstream":null,"dirty":false,"ahead":0,"behind":0,"status":"ready","error":null}"#.utf8))
        var insights = RepositoryInsights.empty
        insights.testFiles = 12
        let record = RepositoryRecord(path: "/demo", name: "demo", fingerprint: "f", insights: insights, git: .empty, scannedAt: Date(), scanMs: 1)
        let run = CubeModel.run(record: record, repository: repository, liveServices: nil)
        XCTAssertEqual(run.measurements.map(\.phase), [1, 2, 3])
        XCTAssertTrue(run.measurements.allSatisfy { (1...3).contains($0.row) && (1...3).contains($0.column) })
        XCTAssertEqual(run.measurements[2].row, 3, "12 tests is high")
        XCTAssertEqual(run.measurements[2].columnMetric.evidence, .unverified, "unknown services stay unverified")
    }

    func testFingerprintChangesWithWorkingTree() {
        XCTAssertEqual(RepositoryFingerprint.make(head: "a", statusPorcelain: "x"), RepositoryFingerprint.make(head: "a", statusPorcelain: "x"))
        XCTAssertNotEqual(RepositoryFingerprint.make(head: "a", statusPorcelain: "x"), RepositoryFingerprint.make(head: "a", statusPorcelain: "y"))
        XCTAssertNotEqual(RepositoryFingerprint.make(head: "a", statusPorcelain: "x"), RepositoryFingerprint.make(head: "b", statusPorcelain: "x"))
    }

    func testDiscoveryExcludesBackupsAndDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("daemon-discovery-\(UUID().uuidString)")
        for path in ["choisys/repo/.git", "daemon-core/.git", "daemon-core.backup-2026/.git", "web/node_modules/pkg/.git"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let names = RepositoryDiscovery.discover(root: root.path).map(\.name)
        XCTAssertEqual(Set(names), ["choisys", "daemon-core"])
    }

    func testTopologyLayoutKeepsUnverifiedHonest() {
        let tailnet = TailnetSnapshot.unavailable("sin Tailscale")
        let definition = TopologyConfig.standard.service("neo-cube")!
        let status = ServiceStatus(definition: definition, machine: .mac, endpoint: "127.0.0.1:8765", probe: nil, listener: nil, stats: .empty, note: "sin listener")
        let snapshot = EcosystemSnapshot(observedAt: Date(), machine: nil, ports: [], portsEvidence: .verified, tailnet: tailnet, services: [status], neon: nil,
                                         cubeExposure: ExposureVerdict(status: "SAFE", reason: "ENGINE_PORT_NOT_LISTENING"), tunnelActive: false, alerts: [], durationMs: 1)
        let layout = TopologyLayout.build(snapshot, config: .standard)
        XCTAssertEqual(layout.nodes.first { $0.id == "m:desktop" }?.evidence, .unverified)
        XCTAssertEqual(layout.nodes.first { $0.id.hasPrefix("s:neo-cube") }?.evidence, .unverified)
        XCTAssertEqual(snapshot.productPath.first { $0.id == "neon" }?.evidence, .unverified)
    }
}

final class ConversationTests: XCTestCase {
    func testFollowUpReusesPreviousIntent() {
        let repos = ["choisys", "daemon-core"]
        let previous = IntentRouter.route("¿qué cambios tiene choisys?", repositories: repos) ?? RoutedIntent(tool: "repo.status", arguments: ["repo": "choisys"], explicitCommand: false)
        XCTAssertTrue(IntentRouter.isFollowUp("¿y daemon-core?"))
        let next = IntentRouter.followUp("¿y daemon-core?", previous: previous, repositories: repos)
        XCTAssertEqual(next?.tool, previous.tool)
        XCTAssertEqual(next?.arguments["repo"], "daemon-core")
        let ports = IntentRouter.followUp("y el 3000", previous: RoutedIntent(tool: "system.ports", arguments: ["port": "8081"], explicitCommand: false), repositories: repos)
        XCTAssertEqual(ports?.arguments["port"], "3000")
        XCTAssertNil(IntentRouter.followUp("¿y daemon-core?", previous: nil, repositories: repos))
    }

    func testVoiceKeepsMeasuredContentAndEmphasis() {
        let outcome = ToolOutcome(text: ":8081 lo usa node (PID 12) en 127.0.0.1, CPU 1.5 %, latencia 40 ms.", evidence: .verified, toolsUsed: ["system.ports"])
        let text = DaemonVoice.compose(question: "¿qué usa 8081?", tool: "system.ports", outcome: outcome)
        XCTAssertTrue(text.contains("**:8081**"))
        XCTAssertTrue(text.contains("**40 ms**"))
        XCTAssertTrue(text.contains("PID 12"))
        XCTAssertEqual(DaemonVoice.compose(question: "a", tool: "x", outcome: outcome), DaemonVoice.compose(question: "a", tool: "x", outcome: outcome), "deterministic")
        let unverified = DaemonVoice.compose(question: "b", tool: nil, outcome: ToolOutcome(text: "nada", evidence: .unverified))
        XCTAssertFalse(unverified.lowercased().contains("lo acabo de medir"))
    }
}
