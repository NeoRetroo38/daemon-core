#if os(macOS)
import Foundation
import SwiftUI

/// Paso visible del razonamiento de un agente (como el tool use de un LLM).
public struct TraceStep: Identifiable, Sendable, Hashable {
    public enum State: Sendable, Hashable { case running, done, failed }
    public let id = UUID()
    public var label: String
    public var detail: String
    public var state: State
    public var milliseconds: Int?
}

public struct ChatMessage: Identifiable, Sendable {
    public enum Role: String, Sendable { case neo, daemon, clod }
    public let id = UUID()
    public let role: Role
    /// Texto mostrado (crece mientras se «escribe»).
    public var text: String
    public var blocks: [AgentBlock]
    public var evidence: Evidence?
    public var tools: [String]
    public let timestamp = Date()
    public var pending: Bool
    public var engine: String
    public var trace: [TraceStep] = []
    public var streaming = false

    public init(role: Role, text: String, blocks: [AgentBlock] = [], evidence: Evidence? = nil, tools: [String] = [],
                pending: Bool = false, engine: String = "") {
        self.role = role
        self.text = text
        self.blocks = blocks
        self.evidence = evidence
        self.tools = tools
        self.pending = pending
        self.engine = engine
    }
}

/// Revela texto a ritmo de lectura, como un modelo que genera tokens.
@MainActor
enum Typewriter {
    static func reveal(_ full: String, update: @escaping @MainActor (String, Bool) -> Void) async {
        var shown = ""
        var remaining = Substring(full)
        while !remaining.isEmpty {
            // Trozos de 1–4 «tokens» (palabras o signos) con pausas cortas y naturales.
            let take = Int.random(in: 1...4)
            var chunk = ""
            for _ in 0..<take {
                guard let next = remaining.firstIndex(where: { $0 == " " || $0 == "\n" }) else { chunk += remaining; remaining = ""; break }
                let end = remaining.index(after: next)
                chunk += remaining[..<end]
                remaining = remaining[end...]
            }
            shown += chunk
            update(shown, true)
            let pause: UInt64 = chunk.contains(".") || chunk.contains("\n") ? 70_000_000 : UInt64.random(in: 18_000_000...38_000_000)
            try? await Task.sleep(nanoseconds: pause)
        }
        update(full, false)
    }
}

/// Conversación con Daemon. El router entiende la intención y las
/// herramientas miden; la respuesta se redacta en lenguaje natural (con el
/// LLM si hay API key, o con la voz local de Daemon) y llega «escribiéndose».
@MainActor
public final class AgentSession: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var busy = false
    @Published public private(set) var lastEcosystem: EcosystemSnapshot?
    private let contextProvider: @MainActor () -> AgentContext
    /// Memoria de la conversación para las preguntas de seguimiento.
    private var lastIntent: RoutedIntent?

    public init(context: @escaping @MainActor () -> AgentContext) {
        self.contextProvider = context
    }

    public var llmEnabled: Bool { AgentKeychain.configured }

    public func send(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        messages.append(ChatMessage(role: .neo, text: question))
        let context = contextProvider()
        let names = context.repositories.map(\.name)
        var routed = IntentRouter.route(question, repositories: names)
        if routed == nil || (routed?.tool == "repo.status" && lastIntent != nil && IntentRouter.isFollowUp(question)) {
            routed = IntentRouter.followUp(question, previous: lastIntent, repositories: names) ?? routed
        }
        if let routed { lastIntent = routed }
        let history = messages.dropLast().suffix(10).map { (role: $0.role == .neo ? "user" : "assistant", text: $0.text) }
        let index = beginReply()
        Task { await self.answer(question, routed: routed, context: context, history: Array(history), index: index) }
    }

    /// Ejecuta una acción contextual pulsada por Neo (cuenta como aprobación).
    public func perform(_ action: AgentAction) {
        guard !busy else { return }
        messages.append(ChatMessage(role: .neo, text: action.title))
        let context = contextProvider()
        let index = beginReply()
        Task {
            let outcome = await self.runTool(action.tool, arguments: action.arguments, context: context, approval: .userConfirmed, index: index)
            await self.finish(index, question: action.title, tool: action.tool, outcome: outcome, history: [])
        }
    }

    public func clear() { messages.removeAll(); lastIntent = nil }

    // MARK: - Ciclo de respuesta

    private func beginReply() -> Int {
        busy = true
        var message = ChatMessage(role: .daemon, text: "", pending: true)
        message.trace = [TraceStep(label: "Leyendo la pregunta", detail: "", state: .running)]
        messages.append(message)
        return messages.count - 1
    }

    private func setTrace(_ index: Int, _ change: (inout [TraceStep]) -> Void) {
        guard messages.indices.contains(index) else { return }
        change(&messages[index].trace)
    }

    private func runTool(_ tool: String, arguments: [String: String], context: AgentContext, approval: ExecutionApproval, index: Int) async -> ToolOutcome {
        let spec = ToolCatalog.spec(tool)
        setTrace(index) { trace in
            if let first = trace.indices.first, trace[first].state == .running { trace[first].state = .done }
            let args = arguments.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            trace.append(TraceStep(label: tool + (args.isEmpty ? "" : " · " + args), detail: spec?.technology ?? "", state: .running))
        }
        let started = Date()
        let outcome = await ToolExecutor.run(tool, arguments: arguments, context: context, approval: approval)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        setTrace(index) { trace in
            guard let last = trace.indices.last else { return }
            trace[last].state = outcome.evidence == .failed ? .failed : .done
            trace[last].milliseconds = elapsed
        }
        for block in outcome.blocks { if case .topology(let snapshot) = block { lastEcosystem = snapshot } }
        return outcome
    }

    private func answer(_ question: String, routed: RoutedIntent?, context: AgentContext,
                        history: [(role: String, text: String)], index: Int) async {
        if let routed, let spec = ToolCatalog.spec(routed.tool) {
            let needsButton = spec.risk != .read && (spec.requiresConfirmation || !routed.explicitCommand)
            if needsButton {
                setTrace(index) { $0[0].state = .done }
                var outcome = ToolOutcome(text: "", blocks: [.actions([AgentAction(title: spec.description, tool: spec.name, arguments: routed.arguments)])],
                                          evidence: .unverified, toolsUsed: [])
                if routed.tool == "neon.health", let cached = DaemonStore.read(NeonReport.self, from: "snapshots/neon.json") {
                    outcome.text = "último diagnóstico: \(cached.ok == true ? "correcto" : (cached.errorCode ?? "incompleto")), \(cached.durationMs) ms, \(DaemonClock.relative(cached.provenance.observedAt))"
                }
                await finish(index, question: question, tool: routed.tool, outcome: outcome, history: history, proposal: spec)
                return
            }
            let outcome = await runTool(routed.tool, arguments: routed.arguments, context: context,
                                        approval: spec.risk == .read ? .automatic : .userConfirmed, index: index)
            await finish(index, question: question, tool: routed.tool, outcome: outcome, history: history)
            return
        }
        if AgentKeychain.configured {
            setTrace(index) { trace in
                trace[0].state = .done
                trace.append(TraceStep(label: "Razonando con \(AgentSettings.model)", detail: "solo herramientas de lectura", state: .running))
            }
            let digest = await RepositoryIndex.shared.digest(for: context.repositories)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let digestText = (try? encoder.encode(digest)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let ecosystemText = context.ecosystem.map(Self.compact) ?? "sin observación"
            var outcome: ToolOutcome
            do {
                outcome = try await ClaudeAgent.respond(to: question, history: history, context: context, digest: digestText, ecosystem: ecosystemText)
                outcome.toolsUsed.insert("llm:\(AgentSettings.model)", at: 0)
            } catch {
                outcome = ToolOutcome(text: "No llego al modelo (\(error.localizedDescription)). Sigo en local: pregúntame algo concreto sobre repos, puertos, red, choisys o el Cubo.", evidence: .unverified)
            }
            setTrace(index) { trace in if let last = trace.indices.last { trace[last].state = .done } }
            await finish(index, question: question, tool: nil, outcome: outcome, history: history, alreadyPhrased: true)
            return
        }
        setTrace(index) { $0[0].state = .done }
        let overview = await runTool("repo.list", arguments: [:], context: context, approval: .automatic, index: index)
        await finish(index, question: question, tool: nil, outcome: overview, history: history)
    }

    /// Redacta y «escribe» la respuesta final.
    private func finish(_ index: Int, question: String, tool: String?, outcome: ToolOutcome, history: [(role: String, text: String)],
                        proposal: ToolSpec? = nil, alreadyPhrased: Bool = false) async {
        guard messages.indices.contains(index) else { busy = false; return }
        messages[index].pending = false
        messages[index].streaming = true
        messages[index].evidence = proposal == nil ? outcome.evidence : nil
        messages[index].tools = outcome.toolsUsed
        if !alreadyPhrased && AgentKeychain.configured && proposal == nil {
            // Voz del LLM sobre resultados medidos, en streaming real.
            messages[index].engine = AgentSettings.model
            do {
                let stream = ClaudeAgent.composeStream(question: question, history: history, toolName: tool ?? "", outcome: outcome)
                for try await chunk in stream {
                    messages[index].text += chunk
                }
            } catch {
                messages[index].text = ""
            }
        }
        if messages[index].text.isEmpty {
            let full = alreadyPhrased ? outcome.text : DaemonVoice.compose(question: question, tool: tool, outcome: outcome, proposal: proposal)
            messages[index].engine = alreadyPhrased ? AgentSettings.model : "local"
            await Typewriter.reveal(full) { [weak self] shown, _ in
                guard let self, self.messages.indices.contains(index) else { return }
                self.messages[index].text = shown
            }
        }
        withAnimation(.easeOut(duration: 0.3)) {
            messages[index].blocks = outcome.blocks
            messages[index].streaming = false
        }
        busy = false
        if proposal == nil { SoundBoard.shared.play(for: outcome.evidence) }
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
