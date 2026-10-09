import Foundation

/// Acción contextual que Neo puede pulsar desde una respuesta.
public struct AgentAction: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let title: String
    public let tool: String
    public let arguments: [String: String]
    public let risk: ToolRisk
    public let needsConfirmation: Bool

    public init(title: String, tool: String, arguments: [String: String] = [:]) {
        self.title = title
        self.tool = tool
        self.arguments = arguments
        let spec = ToolCatalog.spec(tool)
        self.risk = spec?.risk ?? .read
        self.needsConfirmation = spec?.requiresConfirmation ?? false
    }
}

/// Bloques visuales vivos que una respuesta puede incluir además del texto.
public enum AgentBlock: Sendable, Identifiable {
    case metrics([Metric])
    case services([ServiceStatus])
    case path([PathHop])
    case ports([ListeningSocket])
    case tailnet(TailnetSnapshot)
    case commits([CommitEvent], title: String)
    case changes([FileChange])
    case pullRequests([PullRequestInfo], slug: String)
    case runs([WorkflowRunInfo])
    case code(title: String, text: String)
    case alerts([DaemonAlert])
    case cube(repository: RepositorySnapshot, record: RepositoryRecord)
    case topology(EcosystemSnapshot)
    case tools([ToolInfo])
    case provenance(Provenance, Evidence)
    case actions([AgentAction])

    public var id: String {
        switch self {
        case .metrics: "metrics"
        case .services: "services"
        case .path: "path"
        case .ports: "ports"
        case .tailnet: "tailnet"
        case .commits(_, let title): "commits-\(title)"
        case .changes: "changes"
        case .pullRequests(_, let slug): "prs-\(slug)"
        case .runs: "runs"
        case .code(let title, _): "code-\(title)"
        case .alerts: "alerts"
        case .cube(let repository, _): "cube-\(repository.path)"
        case .topology: "topology"
        case .tools: "tools"
        case .provenance: "provenance"
        case .actions: "actions"
        }
    }
}

public struct ToolOutcome: Sendable {
    public var text: String
    public var blocks: [AgentBlock]
    public var evidence: Evidence
    public var toolsUsed: [String]

    public init(text: String, blocks: [AgentBlock] = [], evidence: Evidence = .verified, toolsUsed: [String] = []) {
        self.text = text
        self.blocks = blocks
        self.evidence = evidence
        self.toolsUsed = toolsUsed
    }

    /// Texto compacto para devolver a un LLM como resultado de herramienta.
    public var digest: String {
        var lines = [text]
        for block in blocks {
            switch block {
            case .metrics(let metrics): lines += metrics.map { "\($0.label): \($0.display) [\($0.evidence.label); \($0.provenance.source)]" }
            case .services(let services): lines += services.map { "\($0.definition.name)@\($0.machine.rawValue): \($0.label) [\($0.evidence.label)]" }
            case .path(let hops): lines += hops.map { "\($0.name): \($0.detail) [\($0.evidence.label)]" }
            case .ports(let sockets): lines += sockets.prefix(30).map { ":\($0.port) \($0.command) pid \($0.pid) \($0.address) (\($0.scope.label))" }
            case .tailnet(let tailnet): lines += tailnet.peers.map { "\($0.shortName) \($0.os) \($0.online ? "online" : "offline") \($0.ipv4 ?? "")" }
            case .commits(let commits, _): lines += commits.prefix(15).map { "\($0.shortHash) \($0.subject)" }
            case .changes(let changes): lines += changes.prefix(30).map { "\($0.path) +\($0.added ?? 0) -\($0.removed ?? 0)" }
            case .pullRequests(let prs, _): lines += prs.map { "#\($0.number) \($0.state) \($0.title) (\($0.headRefName))" }
            case .runs(let runs): lines += runs.map { "\($0.name ?? "run") \($0.status) \($0.conclusion ?? "")" }
            case .code(_, let text): lines.append(String(text.prefix(1500)))
            case .alerts(let alerts): lines += alerts.map { "[\($0.level.rawValue)] \($0.title): \($0.detail)" }
            case .tools(let tools): lines += tools.map { "\($0.name) \($0.version ?? "?") \($0.installed ? "instalado" : "no encontrado")" }
            default: continue
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Contexto vivo que el agente consulta antes de lanzar herramientas.
public struct AgentContext: Sendable {
    public let repositories: [RepositorySnapshot]
    public let ecosystem: EcosystemSnapshot?
    public let config: TopologyConfig
    public let selectedRepositoryPath: String?

    public init(repositories: [RepositorySnapshot], ecosystem: EcosystemSnapshot?, config: TopologyConfig, selectedRepositoryPath: String?) {
        self.repositories = repositories
        self.ecosystem = ecosystem
        self.config = config
        self.selectedRepositoryPath = selectedRepositoryPath
    }

    /// Resuelve un nombre de repo (o alias) contra el catálogo.
    public func repository(named raw: String?) -> RepositorySnapshot? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else {
            return repositories.first { $0.path == selectedRepositoryPath }
        }
        let aliases = ["daemon": "daemon-core", "cubo": "cubo-de-neo", "neos-cube": "cubo-de-neo", "landing": "scenarys", "web": "neo-cube-web"]
        let wanted = aliases[raw] ?? raw
        return repositories.first { $0.name.lowercased() == wanted }
            ?? repositories.first { $0.name.lowercased().contains(wanted) }
    }
}
