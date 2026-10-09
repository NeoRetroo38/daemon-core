#if os(macOS)
import Foundation
import SwiftUI

public struct ChatMessage: Identifiable, Sendable {
    public enum Role: String, Sendable { case neo, daemon }
    public let id = UUID()
    public let role: Role
    public var text: String
    public var blocks: [AgentBlock]
    public var evidence: Evidence?
    public var tools: [String]
    public let timestamp = Date()
    public var pending: Bool
    public var engine: String
}

/// Conversación con Daemon. El router local resuelve la mayoría de preguntas
/// con herramientas y datos medidos; el LLM solo entra si hay API key y no
/// hay intención reconocida.
@MainActor
public final class AgentSession: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var busy = false
    @Published public private(set) var lastEcosystem: EcosystemSnapshot?
    private let contextProvider: @MainActor () -> AgentContext

    public init(context: @escaping @MainActor () -> AgentContext) {
        self.contextProvider = context
    }

    public var llmEnabled: Bool { AgentKeychain.configured }

    public func send(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        messages.append(ChatMessage(role: .neo, text: question, blocks: [], evidence: nil, tools: [], pending: false, engine: ""))
        let context = contextProvider()
        let routed = IntentRouter.route(question, repositories: context.repositories.map(\.name))
        let history = messages.dropLast().suffix(8).map { (role: $0.role == .neo ? "user" : "assistant", text: $0.text) }
        start { [weak self] in
            await self?.answer(question, routed: routed, context: context, history: Array(history)) ?? ToolOutcome(text: "")
        }
    }

    /// Ejecuta una acción contextual pulsada por Neo (cuenta como aprobación).
    public func perform(_ action: AgentAction) {
        guard !busy else { return }
        messages.append(ChatMessage(role: .neo, text: "▸ \(action.title)", blocks: [], evidence: nil, tools: [], pending: false, engine: ""))
        let context = contextProvider()
        start { await ToolExecutor.run(action.tool, arguments: action.arguments, context: context, approval: .userConfirmed) }
    }

    public func clear() { messages.removeAll() }

    private func start(_ work: @escaping @Sendable () async -> ToolOutcome) {
        busy = true
        messages.append(ChatMessage(role: .daemon, text: "midiendo…", blocks: [], evidence: nil, tools: [], pending: true, engine: ""))
        let index = messages.count - 1
        Task { [weak self] in
            let outcome = await work()
            guard let self else { return }
            self.messages[index].text = outcome.text
            self.messages[index].blocks = outcome.blocks
            self.messages[index].evidence = outcome.evidence
            self.messages[index].tools = outcome.toolsUsed
            self.messages[index].pending = false
            self.messages[index].engine = outcome.toolsUsed.isEmpty ? "local" : (self.messages[index].engine.isEmpty ? "local" : self.messages[index].engine)
            for block in outcome.blocks { if case .topology(let snapshot) = block { self.lastEcosystem = snapshot } }
            self.busy = false
        }
    }

    nonisolated private func answer(_ question: String, routed: RoutedIntent?, context: AgentContext,
                                    history: [(role: String, text: String)]) async -> ToolOutcome {
        if let routed, let spec = ToolCatalog.spec(routed.tool) {
            if spec.risk == .read {
                return await ToolExecutor.run(routed.tool, arguments: routed.arguments, context: context, approval: .automatic)
            }
            if spec.requiresConfirmation || !routed.explicitCommand {
                var text = spec.requiresConfirmation
                    ? "«\(spec.description)» es una acción de nivel \(spec.risk.label) que pide confirmación explícita."
                    : "Puedo hacerlo (\(spec.risk.label)). Pídemelo con una orden o pulsa el botón."
                if routed.tool == "neon.health", let cached = DaemonStore.read(NeonReport.self, from: "snapshots/neon.json") {
                    text += " Último diagnóstico: \(cached.ok == true ? "correcto" : (cached.errorCode ?? "incompleto")) · \(cached.durationMs) ms · \(DaemonClock.relative(cached.provenance.observedAt))."
                }
                return ToolOutcome(text: text, blocks: [.actions([AgentAction(title: spec.description, tool: spec.name, arguments: routed.arguments)])],
                                   evidence: .unverified)
            }
            return await ToolExecutor.run(routed.tool, arguments: routed.arguments, context: context, approval: .userConfirmed)
        }
        if AgentKeychain.configured {
            let digest = await RepositoryIndex.shared.digest(for: context.repositories)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let digestText = (try? encoder.encode(digest)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let ecosystemText = context.ecosystem.map(Self.compact) ?? "sin observación"
            do {
                var outcome = try await ClaudeAgent.respond(to: question, history: history, context: context, digest: digestText, ecosystem: ecosystemText)
                outcome.toolsUsed.insert("llm:\(AgentSettings.model)", at: 0)
                return outcome
            } catch {
                return ToolOutcome(text: "El adaptador LLM falló (\(error.localizedDescription)). Sigo en modo local: prueba con una pregunta concreta sobre repos, puertos, red, choisys o el Cubo.", evidence: .unverified)
            }
        }
        var outcome = await ToolExecutor.run("repo.list", context: context, approval: .automatic)
        outcome.text = "No reconozco una herramienta para eso y no hay LLM configurado, así que no voy a improvisar. Esto es lo que sí sé medido: " + outcome.text +
            "\nPrueba: «¿cómo está choisys?», «¿qué proceso usa 8081?», «comprueba la tailnet», «¿qué ha cambiado hoy?», «ejecuta los tests de daemon-core»."
        return outcome
    }

    nonisolated static func compact(_ snapshot: EcosystemSnapshot) -> String {
        var lines = ["observado \(DaemonClock.iso(snapshot.observedAt))"]
        lines += snapshot.services.map { "\($0.definition.id)@\($0.machine.rawValue): \($0.label) [\($0.evidence.label)]" }
        lines += snapshot.alerts.map { "alerta \($0.level.rawValue): \($0.title)" }
        lines.append("tailnet \(snapshot.tailnet.backendState): " + snapshot.tailnet.peers.map { "\($0.shortName)=\($0.online ? "on" : "off")" }.joined(separator: ", "))
        lines.append("puertos: " + snapshot.ports.map { ":\($0.port) \($0.command) \($0.scope.rawValue)" }.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}
#endif
