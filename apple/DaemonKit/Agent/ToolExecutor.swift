#if os(macOS)
import AppKit
import Foundation

/// Ejecuta herramientas declaradas en `ToolCatalog`. Cada herramienta mide,
/// declara su procedencia y nunca ejecuta texto libre.
public enum ToolExecutor {
    public static func run(_ name: String, arguments: [String: String] = [:], context: AgentContext,
                           approval: ExecutionApproval) async -> ToolOutcome {
        guard let spec = ToolCatalog.spec(name) else { return ToolOutcome(text: "No conozco la herramienta \(name).", evidence: .unverified) }
        if spec.risk != .read && approval == .automatic {
            return ToolOutcome(text: "\(name) es de nivel \(spec.risk.label): necesito tu confirmación.",
                               blocks: [.actions([AgentAction(title: "Ejecutar \(name)", tool: name, arguments: arguments)])], evidence: .unverified)
        }
        var outcome = await dispatch(name, arguments, context)
        outcome.toolsUsed.append(name)
        return outcome
    }

    static func dispatch(_ name: String, _ arguments: [String: String], _ context: AgentContext) async -> ToolOutcome {
        switch name {
        case "repo.list": return repoList(context)
        case "repo.status": return await repoStatus(arguments["repo"], context)
        case "repo.diff": return await repoDiff(arguments["repo"], context)
        case "repo.metrics": return await repoMetrics(arguments["repo"], context)
        case "repo.timeline": return await repoTimeline(arguments["repo"], since: arguments["since"], context)
        case "repo.cube": return await repoCube(arguments["repo"], context)
        case "repo.open": return repoOpen(arguments["repo"], context)
        case "repo.tests": return await repoTests(arguments["repo"], context)
        case "daemon.build": return await daemonScript("apple-build-macos.sh", title: "Build de Daemon", context)
        case "daemon.install": return await daemonScript("install-daemon-macos.sh", title: "Instalación de Daemon", context)
        case "github.prs", "github.issues", "github.actions": return await github(name, arguments["repo"], context)
        case "system.resources": return systemResources()
        case "system.ports": return await systemPorts(arguments["port"].flatMap { UInt16($0) }, context)
        case "service.health", "network.topology", "choisys.health": return await services(name, arguments["service"], context)
        case "service.stop": return await serviceStop(arguments["port"].flatMap { UInt16($0) }, context)
        case "network.tailnet": return await tailnet()
        case "cube.health": return await cubeHealth(context)
        case "cube.tunnel.open": return await CubeTunnel.shared.open(config: context.config)
        case "cube.tunnel.close": return await CubeTunnel.shared.close()
        case "choisys.users": return choisysUsers()
        case "neon.health": return await neon(context)
        case "toolchain.inventory": return await toolchain()
        default: return ToolOutcome(text: "Herramienta declarada sin implementación: \(name).", evidence: .unverified)
        }
    }

    // MARK: Repositorios

    static func missing(_ raw: String?, _ context: AgentContext) -> ToolOutcome {
        let names = context.repositories.map(\.name).joined(separator: ", ")
        return ToolOutcome(text: raw.map { "No encuentro «\($0)» en el catálogo. Tengo: \(names)." } ?? "¿Qué repositorio? Tengo: \(names).", evidence: .unverified)
    }

    static func repoList(_ context: AgentContext) -> ToolOutcome {
        let dirty = context.repositories.filter { $0.dirty == true }
        let behind = context.repositories.filter { ($0.behind ?? 0) > 0 }
        var text = "\(context.repositories.count) repos en el catálogo. "
        text += dirty.isEmpty ? "Ninguno con cambios locales. " : "Con cambios locales: \(dirty.map(\.name).joined(separator: ", ")). "
        if !behind.isEmpty { text += "Por detrás de su upstream (según la última copia local del remoto): \(behind.map { "\($0.name) −\($0.behind ?? 0)" }.joined(separator: ", "))." }
        let metrics = context.repositories.map { repo in
            Metric(id: repo.path, label: repo.name, value: nil,
                   display: "\(repo.branch ?? "?") · \(repo.workingTreeLabel.lowercased()) · \(repo.comparisonLabel)",
                   evidence: repo.evidence == .verified ? .verified : .unverified,
                   provenance: Provenance(source: "núcleo C++ (daemon_snapshot_json_many)", method: "git status --porcelain=v2 --branch"))
        }
        return ToolOutcome(text: text, blocks: [.metrics(metrics)])
    }

    static func repoStatus(_ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        guard raw != nil || context.selectedRepositoryPath != nil else { return repoList(context) }
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let record = await RepositoryIndex.shared.record(for: repo)
        var text = "\(repo.name) en \(repo.branch ?? "rama no verificada") @ \(repo.head.map { String($0.prefix(7)) } ?? "?"). \(repo.workingTreeLabel). \(repo.comparisonLabel)."
        if !record.git.workingChanges.isEmpty || (record.git.untrackedCount ?? 0) > 0 {
            text += " \(record.git.workingChanges.count) archivos modificados (+\(record.git.linesAdded) −\(record.git.linesRemoved)) y \(record.git.untrackedCount ?? 0) sin seguimiento."
        }
        var blocks: [AgentBlock] = []
        if !record.git.workingChanges.isEmpty { blocks.append(.changes(record.git.workingChanges)) }
        blocks.append(.actions([AgentAction(title: "Ver diff", tool: "repo.diff", arguments: ["repo": repo.name]),
                                AgentAction(title: "Ejecutar tests", tool: "repo.tests", arguments: ["repo": repo.name]),
                                AgentAction(title: "Abrir en Finder", tool: "repo.open", arguments: ["repo": repo.name])]))
        return ToolOutcome(text: text, blocks: blocks, evidence: repo.evidence == .verified ? .verified : .unverified)
    }

    static func repoDiff(_ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let stat = await GitInsightsProbe.diffStat(path: repo.path)
        return ToolOutcome(text: "Diff de trabajo de \(repo.name) frente a HEAD (resumen, salida redactada por el núcleo):",
                           blocks: [.code(title: "git diff --stat HEAD · \(repo.name)", text: stat)])
    }

    static func repoMetrics(_ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let record = await RepositoryIndex.shared.record(for: repo)
        let source = Provenance(source: record.reused ? "índice local (reutilizado)" : "escaneo local", method: "FileManager · git", observedAt: record.scannedAt)
        let metrics: [Metric] = [
            Metric(id: "files", label: "Archivos", value: Double(record.insights.fileCount), provenance: source),
            Metric(id: "lines", label: "Líneas de código", value: Double(record.insights.sourceLines), provenance: source),
            Metric(id: "tests", label: "Archivos de test", value: Double(record.insights.testFiles), provenance: source),
            Metric(id: "commits", label: "Commits", value: record.git.commitCount.map(Double.init), provenance: record.git.provenance),
            Metric(id: "week", label: "Commits 7 días", value: record.git.commitsLast7Days.map(Double.init), provenance: record.git.provenance),
            Metric(id: "branches", label: "Ramas", value: record.git.branchCount.map(Double.init), provenance: record.git.provenance),
            Metric(id: "changes", label: "Archivos cambiados", value: Double(record.git.workingChanges.count), provenance: record.git.provenance),
        ]
        let languages = record.insights.languages.prefix(4).map { "\($0.name) \($0.files)" }.joined(separator: ", ")
        return ToolOutcome(text: "\(repo.name): \(languages). Gestores: \(record.insights.packageManagers.joined(separator: ", ")). Escaneo \(record.reused ? "reutilizado del índice (huella Git sin cambios)" : "nuevo en \(record.scanMs) ms").",
                           blocks: [.metrics(metrics), .cube(repository: repo, record: record)])
    }

    static func repoTimeline(_ raw: String?, since: String?, _ context: AgentContext) async -> ToolOutcome {
        let repos = raw.flatMap { context.repository(named: $0) }.map { [$0] } ?? context.repositories
        let midnight = Calendar.current.startOfDay(for: Date())
        var events: [CommitEvent] = []
        var dirty: [String] = []
        for repo in repos {
            let record = await RepositoryIndex.shared.record(for: repo)
            events += record.git.recent.map { CommitEvent(hash: $0.hash, timestamp: $0.timestamp, subject: "[\(repo.name)] \($0.subject)", author: $0.author) }
            if !record.git.workingChanges.isEmpty { dirty.append("\(repo.name) (\(record.git.workingChanges.count))") }
        }
        events.sort { $0.timestamp > $1.timestamp }
        let today = events.filter { $0.timestamp >= midnight }
        let shown = since == "today" ? today : Array(events.prefix(15))
        var text = since == "today" ? "Hoy: \(today.count) commits en \(Set(today.map { $0.subject.split(separator: "]").first ?? "" }).count) repos." : "Últimos commits."
        if !dirty.isEmpty { text += " Cambios sin commit en \(dirty.joined(separator: ", "))." }
        if shown.isEmpty { text += " Sin commits en el periodo." }
        return ToolOutcome(text: text, blocks: shown.isEmpty ? [] : [.commits(shown, title: since == "today" ? "Hoy" : "Recientes")])
    }

    static func repoCube(_ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let record = await RepositoryIndex.shared.record(for: repo)
        return ToolOutcome(text: "Cubo de \(repo.name): tres capas (código · Git · operación), cada métrica es una posición fila×columna. Selecciona un punto para ver su procedencia.",
                           blocks: [.cube(repository: repo, record: record)])
    }

    static func repoOpen(_ raw: String?, _ context: AgentContext) -> ToolOutcome {
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let url = URL(fileURLWithPath: repo.path, isDirectory: true)
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        return ToolOutcome(text: "Abierto \(repo.name) en Finder: \(repo.path)")
    }

    static func testPlan(for repo: RepositorySnapshot) -> [(tool: String, arguments: [String], env: [String: String])] {
        let manager = FileManager.default
        func exists(_ file: String) -> Bool { manager.fileExists(atPath: repo.path + "/" + file) }
        var plan: [(String, [String], [String: String])] = []
        let sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
        let env = manager.fileExists(atPath: sdk) ? ["SDKROOT": sdk] : [:]
        if exists("Package.swift") { plan.append(("swift", ["test", "--scratch-path", "build/apple-spm"], [:])) }
        if exists("Makefile") && exists("tests/core-tests.cpp") { plan.append(("make", ["test"], env)) }
        if exists("package.json"),
           let data = manager.contents(atPath: repo.path + "/package.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["scripts"] as? [String: Any])?["test"] != nil { plan.append(("npm", ["test"], [:])) }
        return plan
    }

    static func repoTests(_ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        guard let repo = context.repository(named: raw) else { return missing(raw, context) }
        let plan = testPlan(for: repo)
        guard !plan.isEmpty else { return ToolOutcome(text: "No encuentro una batería de tests conocida en \(repo.name).", evidence: .unverified) }
        var lines: [String] = []
        var evidences: [Evidence] = []
        var metrics: [Metric] = []
        for step in plan {
            let label = "\(step.tool) \(step.arguments.joined(separator: " "))"
            do {
                let result = try await CommandRunner.run(step.tool, step.arguments, in: repo.path, timeout: 900,
                                                         approval: .userConfirmed, extraEnvironment: step.env)
                evidences.append(result.succeeded ? .verified : .failed)
                metrics.append(Metric(id: label, label: label, value: Double(result.durationMs) / 1000,
                                      display: "\(result.succeeded ? "✓ pasa" : "✗ falla (\(result.exitCode))") · \(String(format: "%.1f", Double(result.durationMs) / 1000)) s",
                                      evidence: result.succeeded ? .verified : .failed,
                                      provenance: Provenance(source: repo.name, method: label)))
                let tail = result.displayOutput.split(whereSeparator: \.isNewline).suffix(8).joined(separator: "\n")
                lines.append("$ \(label)\n\(tail)")
            } catch {
                evidences.append(.unverified)
                lines.append("$ \(label)\n\(error.localizedDescription)")
            }
        }
        let evidence = Evidence.weakest(evidences)
        return ToolOutcome(text: evidence == .verified ? "Tests de \(repo.name) en verde." : "Tests de \(repo.name): \(evidence.label). Mira el resumen.",
                           blocks: [.metrics(metrics), .code(title: "tests · \(repo.name)", text: lines.joined(separator: "\n\n"))], evidence: evidence)
    }

    static func daemonScript(_ script: String, title: String, _ context: AgentContext) async -> ToolOutcome {
        guard let repo = context.repository(named: "daemon-core") else { return missing("daemon-core", context) }
        guard FileManager.default.fileExists(atPath: repo.path + "/scripts/" + script) else {
            return ToolOutcome(text: "No existe scripts/\(script) en daemon-core.", evidence: .unverified)
        }
        do {
            let result = try await CommandRunner.run("/bin/bash", ["scripts/" + script], in: repo.path, timeout: 1200, approval: .userConfirmed)
            let tail = result.displayOutput.split(whereSeparator: \.isNewline).suffix(12).joined(separator: "\n")
            return ToolOutcome(text: result.succeeded ? "\(title): correcto en \(result.durationMs / 1000) s." : "\(title) falló (código \(result.exitCode)).",
                               blocks: [.code(title: title, text: tail)] + (script.hasPrefix("apple-build") && result.succeeded
                                    ? [.actions([AgentAction(title: "Instalar en /Applications", tool: "daemon.install")])] : []),
                               evidence: result.succeeded ? .verified : .failed)
        } catch {
            return ToolOutcome(text: "\(title) no se ejecutó: \(error.localizedDescription)", evidence: .unverified)
        }
    }

    // MARK: GitHub

    static func github(_ name: String, _ raw: String?, _ context: AgentContext) async -> ToolOutcome {
        let targets = raw.flatMap { context.repository(named: $0) }.map { [$0] } ?? (context.repository(named: nil).map { [$0] } ?? context.repositories)
        var blocks: [AgentBlock] = []
        var summary: [String] = []
        var evidences: [Evidence] = []
        for repo in targets {
            let record = await RepositoryIndex.shared.record(for: repo)
            guard let slug = record.git.remoteSlug else { continue }
            let snapshot = await GitHubProbe.observe(slug: slug)
            await RepositoryIndex.shared.attachGitHub(snapshot, to: repo.path)
            evidences.append(snapshot.evidence)
            if let error = snapshot.error { summary.append("\(slug): no verificado (\(error))"); continue }
            switch name {
            case "github.prs":
                summary.append("\(slug): \(snapshot.openPullRequests.count) abiertas")
                if !snapshot.pullRequests.isEmpty { blocks.append(.pullRequests(snapshot.pullRequests, slug: slug)) }
            case "github.issues":
                summary.append("\(slug): \(snapshot.issues.count) issues abiertas")
                if !snapshot.issues.isEmpty {
                    blocks.append(.code(title: "issues · \(slug)", text: snapshot.issues.map { "#\($0.number) \($0.title)" }.joined(separator: "\n")))
                }
            default:
                let failing = snapshot.runs.filter { $0.conclusion == "failure" }.count
                summary.append("\(slug): \(snapshot.runs.count) runs recientes, \(failing) fallidos")
                if !snapshot.runs.isEmpty { blocks.append(.runs(snapshot.runs)) }
            }
        }
        if summary.isEmpty { return ToolOutcome(text: "Ningún repo del catálogo tiene un remoto de GitHub reconocible.", evidence: .unverified) }
        return ToolOutcome(text: summary.joined(separator: " · "), blocks: blocks, evidence: Evidence.weakest(evidences))
    }

    // MARK: Sistema y red

    static func systemResources() -> ToolOutcome {
        let machine = SystemProbe.machine()
        let p = machine.provenance
        let gb = 1_073_741_824.0
        var metrics = [
            Metric(id: "cpu", label: "Carga CPU (1 min)", value: machine.loadAverage.first, display: machine.loadAverage.first.map { String(format: "%.2f / %d núcleos", $0, machine.cpuCount) }, provenance: p),
            Metric(id: "ram", label: "Memoria usada", value: machine.memoryUsedBytes.map { Double($0) / gb },
                   display: machine.memoryUsedBytes.map { String(format: "%.1f / %.0f GB", Double($0) / gb, Double(machine.memoryTotalBytes) / gb) }, provenance: p),
            Metric(id: "disk", label: "Disco libre", value: machine.diskAvailableBytes.map { Double($0) / gb },
                   display: machine.diskAvailableBytes.map { String(format: "%.0f GB de %.0f", Double($0) / gb, Double(machine.diskTotalBytes ?? 0) / gb) }, provenance: p),
            Metric(id: "uptime", label: "Uptime", value: machine.uptimeSeconds / 3600, display: String(format: "%.1f h", machine.uptimeSeconds / 3600), provenance: p),
            Metric(id: "thermal", label: "Estado térmico", value: nil, display: machine.thermalState, evidence: .verified,
                   provenance: Provenance(source: "ProcessInfo.thermalState", method: "API de macOS")),
        ]
        if let battery = machine.battery {
            metrics.append(Metric(id: "battery", label: "Batería", value: Double(battery.percent), display: "\(battery.percent) % · \(battery.source)\(battery.charging ? " · cargando" : "")", provenance: p))
        }
        let interfaces = machine.interfaces.filter { $0.scope != .loopback }.map { "\($0.name) \($0.address) (\($0.scope.label))" }.joined(separator: ", ")
        return ToolOutcome(text: "\(machine.hostName) · \(machine.model) · \(machine.osVersion). Interfaces: \(interfaces.isEmpty ? "ninguna activa" : interfaces).",
                           blocks: [.metrics(metrics)])
    }

    static func systemPorts(_ port: UInt16?, _ context: AgentContext) async -> ToolOutcome {
        let result = await PortProbe.listening()
        guard result.evidence != .unverified else { return ToolOutcome(text: "No pude leer los puertos: \(result.error ?? "lsof no disponible").", evidence: .unverified) }
        let sockets = port.map { p in result.sockets.filter { $0.port == p } } ?? result.sockets
        if let port {
            guard let first = sockets.first else {
                return ToolOutcome(text: "Nadie escucha en :\(port) en este Mac (verificado con lsof).", blocks: [.provenance(result.provenance, .verified)])
            }
            let service = context.config.services.first { $0.port == port }
            let memory = first.residentBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "?"
            return ToolOutcome(text: ":\(port) lo usa \(first.command) (PID \(first.pid)) en \(first.address), \(first.scope.label). CPU \(first.cpuPercent.map { String(format: "%.1f %%", $0) } ?? "?"), memoria \(memory), activo \(first.elapsed ?? "?").\(service.map { " Es \($0.name) del repo \($0.repository ?? "?")." } ?? " No es un servicio declarado.")",
                               blocks: [.ports(sockets), .provenance(result.provenance, result.evidence)])
        }
        let exposed = sockets.filter { $0.scope >= .allInterfaces }
        return ToolOutcome(text: "\(sockets.count) listeners TCP. \(exposed.isEmpty ? "Todos limitados a loopback o tailnet." : "\(exposed.count) escuchan en todas las interfaces: \(exposed.map { ":\($0.port) \($0.command)" }.joined(separator: ", ")).")",
                           blocks: [.ports(sockets), .provenance(result.provenance, result.evidence)])
    }

    static func services(_ name: String, _ service: String?, _ context: AgentContext) async -> ToolOutcome {
        let snapshot = await EcosystemProbe.observe(config: context.config)
        switch name {
        case "network.topology":
            let alive = snapshot.services.filter(\.alive).count
            return ToolOutcome(text: "Ecosistema observado en \(snapshot.durationMs) ms: \(alive)/\(snapshot.services.count) sondas responden, \(snapshot.tailnet.peers.count) nodos en la tailnet, \(snapshot.alerts.count) alertas.",
                               blocks: [.topology(snapshot)] + (snapshot.alerts.isEmpty ? [] : [.alerts(snapshot.alerts)]))
        case "choisys.health":
            let broken = snapshot.firstBrokenHop
            let text = broken.map { "La ruta se rompe en \($0.name): \($0.detail)." } ?? "Ningún eslabón falla. Los no verificados aparecen como tales."
            let rows = snapshot.services.filter { ["choisys-web", "choisys-api", "neo-cube", "landing"].contains($0.definition.id) }
            return ToolOutcome(text: text, blocks: [.path(snapshot.productPath), .services(rows)] + (snapshot.alerts.isEmpty ? [] : [.alerts(snapshot.alerts)]) +
                               [.actions([AgentAction(title: "Comprobar Neon", tool: "neon.health")])],
                               evidence: Evidence.weakest(snapshot.productPath.map(\.evidence)))
        default:
            let rows = service.map { id in snapshot.services.filter { $0.definition.id.contains(id) || $0.definition.name.lowercased().contains(id) } } ?? snapshot.services
            let text = rows.map { "\($0.definition.name)@\($0.machine.label): \($0.label)" }.joined(separator: " · ")
            return ToolOutcome(text: text.isEmpty ? "No hay servicios que coincidan." : text, blocks: [.services(rows)], evidence: Evidence.weakest(rows.map(\.evidence)))
        }
    }

    static func serviceStop(_ port: UInt16?, _ context: AgentContext) async -> ToolOutcome {
        guard let port, let service = context.config.services.first(where: { $0.port == port }) else {
            return ToolOutcome(text: "Solo detengo servicios de desarrollo declarados (5173, 8081, 3000, 8765).", evidence: .unverified)
        }
        let result = await PortProbe.listening()
        guard let socket = result.sockets.first(where: { $0.port == port }) else { return ToolOutcome(text: "Nada escucha en :\(port).") }
        guard socket.pid != Int(getpid()) else { return ToolOutcome(text: "No me detengo a mí mismo.", evidence: .unverified) }
        let status = kill(pid_t(socket.pid), SIGTERM)
        return ToolOutcome(text: status == 0 ? "SIGTERM enviado a \(socket.command) (PID \(socket.pid)) de \(service.name)." : "No pude detener el PID \(socket.pid).",
                           evidence: status == 0 ? .verified : .failed)
    }

    static func tailnet() async -> ToolOutcome {
        let snapshot = await TailnetProbe.status()
        guard snapshot.evidence != .unverified else { return ToolOutcome(text: "Tailnet no verificada: \(snapshot.error ?? snapshot.backendState).", evidence: .unverified) }
        let online = snapshot.peers.filter { $0.online && !$0.isSelf }
        return ToolOutcome(text: "Tailscale \(snapshot.backendState)\(snapshot.tailnetName.map { " en \($0)" } ?? ""). \(online.count) nodos en línea: \(online.map(\.shortName).joined(separator: ", ")).",
                           blocks: [.tailnet(snapshot)], evidence: snapshot.evidence)
    }

    static func cubeHealth(_ context: AgentContext) async -> ToolOutcome {
        let snapshot = await EcosystemProbe.observe(config: context.config)
        let cube = snapshot.status("neo-cube")
        var text: String
        let local = cube.first { $0.machine == .mac }
        if snapshot.tunnelActive, local?.alive == true {
            text = "Cubo alcanzable por túnel SSH en 127.0.0.1:8765 → Desktop (\(local?.label ?? ""))."
        } else if local?.alive == true {
            text = "Cubo local vivo en 127.0.0.1:8765: \(local?.label ?? "")."
        } else {
            text = "No hay Cubo en 127.0.0.1:8765 de este Mac."
        }
        text += " Contrato de exposición: \(snapshot.cubeExposure.status) (\(snapshot.cubeExposure.reason))."
        if let desktop = cube.first(where: { $0.machine == .desktop }) {
            text += desktop.alive ? " ⚠︎ El Desktop acepta TCP en \(desktop.endpoint ?? "8765") por la tailnet." : " Desktop: 8765 no accesible por la tailnet (\(desktop.label)), como exige el contrato."
        }
        let actions = snapshot.tunnelActive ? [AgentAction(title: "Cerrar túnel", tool: "cube.tunnel.close")] : [AgentAction(title: "Abrir túnel al Desktop", tool: "cube.tunnel.open")]
        return ToolOutcome(text: text, blocks: [.services(cube)] + (snapshot.alerts.filter { $0.id.hasPrefix("cube") }.isEmpty ? [] : [.alerts(snapshot.alerts.filter { $0.id.hasPrefix("cube") })]) + [.actions(actions)],
                           evidence: Evidence.weakest(cube.map(\.evidence)))
    }

    static func choisysUsers() -> ToolOutcome {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".choisys/auth-v1.json")
        guard let data = try? Data(contentsOf: url) else {
            return ToolOutcome(text: "No hay almacén local autorizado (~/.choisys/auth-v1.json). Con Neon, los usuarios viven en la base de datos y Daemon no lee filas personales.", evidence: .unverified)
        }
        let names = RepositoryInspector.usernames(from: data)
        return ToolOutcome(text: names.isEmpty ? "El almacén local no tiene nombres visibles." : "\(names.count) usuarios: \(names.joined(separator: ", ")). Solo displayName; correo, IDs, roles y hashes se descartan.")
    }

    static func neon(_ context: AgentContext) async -> ToolOutcome {
        let report = await EcosystemProbe.checkNeon(config: context.config)
        let flags = report.flags.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value ? "✓" : "✗")" }.joined(separator: " · ")
        let metrics = [Metric(id: "neon", label: "Diagnóstico Neon", value: Double(report.durationMs), display: "\(report.ok == true ? "correcto" : (report.errorCode ?? "incompleto")) · \(report.durationMs) ms",
                              evidence: report.evidence, provenance: report.provenance)]
        return ToolOutcome(text: report.ok == true ? "Neon responde: \(flags). El tiempo incluye arranque de Node y Prisma, no es latencia pura de red." : "Neon: \(report.evidence.label). \(report.errorCode ?? "") \(flags)",
                           blocks: [.metrics(metrics)], evidence: report.evidence)
    }

    static func toolchain() async -> ToolOutcome {
        let snapshot = await ToolchainProbe.observe()
        let missing = snapshot.tools.filter { !$0.installed }.map(\.name)
        return ToolOutcome(text: "\(snapshot.tools.filter(\.installed).count) herramientas detectadas. No encontradas: \(missing.isEmpty ? "ninguna" : missing.joined(separator: ", ")).",
                           blocks: [.tools(snapshot.tools)])
    }
}

/// Túnel SSH privado Mac → Desktop para el Cubo. Solo -N -L 127.0.0.1.
public actor CubeTunnel {
    public static let shared = CubeTunnel()
    private var process: Process?

    public var active: Bool { process?.isRunning == true }

    public func open(config: TopologyConfig) async -> ToolOutcome {
        if active { return ToolOutcome(text: "El túnel ya está abierto (PID \(process?.processIdentifier ?? 0)).") }
        let ports = await PortProbe.listening()
        if let busy = ports.sockets.first(where: { $0.port == 8765 }) {
            return ToolOutcome(text: "127.0.0.1:8765 ya está ocupado por \(busy.command) (PID \(busy.pid)). No abro otro túnel encima.", evidence: .partial)
        }
        let tailnet = await TailnetProbe.status()
        guard let desktop = tailnet.peer(named: config.desktopHost), desktop.online, let ip = desktop.ipv4 else {
            return ToolOutcome(text: "El Desktop (\(config.desktopHost)) no aparece en línea en la tailnet.", evidence: .unverified)
        }
        guard let user = config.desktopSSHUser, !user.isEmpty else {
            return ToolOutcome(text: "Falta el usuario SSH del Desktop. Añade \"desktopSSHUser\" en ~/Library/Application Support/Daemon/topology.json.", evidence: .unverified)
        }
        guard let ssh = Toolbox.locate("ssh") else { return ToolOutcome(text: "OpenSSH no encontrado.", evidence: .unverified) }
        let arguments = ["-N", "-L", "127.0.0.1:8765:127.0.0.1:8765", "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
                         "-o", "ServerAliveInterval=30", "-o", "ConnectTimeout=8", "\(user)@\(ip)"]
        let decision = CommandRunner.policy(ssh, arguments, approval: .userConfirmed)
        guard decision.verdict == .allow else { return ToolOutcome(text: "El núcleo no permite este túnel: \(decision.reason).", evidence: .failed) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = arguments
        process.environment = CommandRunner.environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ToolOutcome(text: "No pude lanzar ssh: \(error.localizedDescription)", evidence: .failed) }
        self.process = process
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard process.isRunning else {
            self.process = nil
            return ToolOutcome(text: "ssh terminó (código \(process.terminationStatus)). Revisa que el Desktop tenga OpenSSH Server y tu clave autorizada.", evidence: .failed)
        }
        let probe = await NetworkProbe.http(URL(string: "http://127.0.0.1:8765/health")!)
        let record = """
        Túnel abierto · escucha: ssh (PID \(process.processIdentifier)) en 127.0.0.1:8765 · consume: Daemon y choisys API locales · \
        destino: \(config.desktopHost) 127.0.0.1:8765 vía tailnet · cierre: «cierra el túnel» o kill \(process.processIdentifier).
        """
        DaemonStore.write(["opened": DaemonClock.iso(Date()), "pid": String(process.processIdentifier), "record": record], to: "snapshots/tunnel.json")
        return ToolOutcome(text: "\(record)\nSonda: \(probe.summary).", evidence: probe.evidence)
    }

    public func close() async -> ToolOutcome {
        guard let process, process.isRunning else { self.process = nil; return ToolOutcome(text: "No hay túnel abierto por Daemon.") }
        process.terminate()
        self.process = nil
        return ToolOutcome(text: "Túnel cerrado (PID \(process.processIdentifier)).")
    }
}
#endif
