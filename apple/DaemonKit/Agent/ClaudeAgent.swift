import Foundation
import Security

/// API key de Anthropic en el Llavero de macOS. Nunca se escribe en disco,
/// logs ni UserDefaults.
public enum AgentKeychain {
    static let service = "com.scenarys.daemon"
    static let account = "anthropic-api-key"

    public static func read() -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    public static func save(_ key: String) -> Bool {
        delete()
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                         kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    public static var configured: Bool { read() != nil }
}

public enum AgentSettings {
    public static var model: String {
        get { UserDefaults.standard.string(forKey: "daemon.agent.model") ?? "claude-sonnet-5-5" }
        set { UserDefaults.standard.set(newValue, forKey: "daemon.agent.model") }
    }
}

public enum ClaudeAgentError: Error, LocalizedError {
    case notConfigured, http(Int, String), malformed
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Sin API key en el Llavero."
        case .http(let code, let type): "La API respondió \(code) (\(type))."
        case .malformed: "Respuesta de la API no reconocida."
        }
    }
}

#if os(macOS)
/// Adaptador opcional a la API de Claude con tool use. Solo ve herramientas
/// READ del catálogo; nunca una shell.
public enum ClaudeAgent {
    static func wireName(_ tool: String) -> String { tool.replacingOccurrences(of: ".", with: "_") }

    static var toolDefinitions: [[String: Any]] {
        ToolCatalog.all.filter { $0.risk == .read && $0.name != "repo.open" }.map { spec in
            var properties: [String: Any] = [:]
            for input in spec.inputs { properties[input.name] = ["type": "string", "description": input.description] }
            return ["name": wireName(spec.name), "description": "\(spec.description) Salida: \(spec.outputs).",
                    "input_schema": ["type": "object", "properties": properties, "required": spec.inputs.filter(\.required).map(\.name)]]
        }
    }

    public static func respond(to question: String, history: [(role: String, text: String)], context: AgentContext,
                               digest: String, ecosystem: String) async throws -> ToolOutcome {
        try await loop(question: question, history: history, context: context, model: AgentSettings.model,
                       system: DaemonPersona.systemPrompt(digest: digest, ecosystem: ecosystem), extraTools: [], extraHandler: nil)
    }

    /// Bucle de tool use genérico (Daemon y Clod). Las herramientas del
    /// catálogo solo se ofrecen si son READ; las extra las resuelve quien llama.
    public static func loop(question: String, history: [(role: String, text: String)], context: AgentContext, model: String,
                            system: String, extraTools: [[String: Any]],
                            extraHandler: (@Sendable (String, [String: String]) async -> (text: String, blocks: [AgentBlock])?)?) async throws -> ToolOutcome {
        guard let key = AgentKeychain.read() else { throw ClaudeAgentError.notConfigured }
        var messages: [[String: Any]] = history.suffix(10).map { ["role": $0.role, "content": $0.text] }
        // La API exige alternancia empezando por "user".
        while let first = messages.first, first["role"] as? String != "user" { messages.removeFirst() }
        messages.append(["role": "user", "content": question])
        var blocks: [AgentBlock] = []
        var used: [String] = []
        var evidences: [Evidence] = []
        let wireToTool = Dictionary(uniqueKeysWithValues: ToolCatalog.all.map { (wireName($0.name), $0.name) })
        for _ in 0..<6 {
            let body: [String: Any] = ["model": model, "max_tokens": 1600, "system": system,
                                       "tools": toolDefinitions + extraTools, "messages": messages]
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 90)
            request.httpMethod = "POST"
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await NetworkProbe.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeAgentError.malformed }
            guard code == 200 else { throw ClaudeAgentError.http(code, ((root["error"] as? [String: Any])?["type"] as? String) ?? "error") }
            let content = root["content"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": content])
            let calls = content.filter { $0["type"] as? String == "tool_use" }
            if calls.isEmpty || root["stop_reason"] as? String != "tool_use" {
                let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                return ToolOutcome(text: text.isEmpty ? "Sin respuesta." : text, blocks: blocks,
                                   evidence: evidences.isEmpty ? .unverified : Evidence.weakest(evidences), toolsUsed: used)
            }
            var results: [[String: Any]] = []
            for call in calls {
                guard let id = call["id"] as? String, let wire = call["name"] as? String else { continue }
                let input = (call["input"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
                if let tool = wireToTool[wire], ToolCatalog.spec(tool)?.risk == .read {
                    let outcome = await ToolExecutor.run(tool, arguments: input, context: context, approval: .automatic)
                    blocks += outcome.blocks.filter { if case .actions = $0 { return false }; return true }
                    used += outcome.toolsUsed
                    evidences.append(outcome.evidence)
                    results.append(["type": "tool_result", "tool_use_id": id, "content": "[\(outcome.evidence.label)] " + String(outcome.digest.prefix(6000))])
                } else if let extraHandler, let handled = await extraHandler(wire, input) {
                    blocks += handled.blocks
                    used.append(wire)
                    results.append(["type": "tool_result", "tool_use_id": id, "content": String(handled.text.prefix(6000))])
                } else {
                    results.append(["type": "tool_result", "tool_use_id": id, "content": "Herramienta no permitida.", "is_error": true])
                }
            }
            messages.append(["role": "user", "content": results])
        }
        return ToolOutcome(text: "He alcanzado el límite de pasos de herramientas; esto es lo que medí.", blocks: blocks,
                           evidence: Evidence.weakest(evidences), toolsUsed: used)
    }
}

extension ClaudeAgent {
    /// Redacción en streaming (SSE) de una respuesta basada solo en el
    /// resultado medido de una herramienta. Sin tools: no puede inventar acciones.
    public static func composeStream(question: String, history: [(role: String, text: String)], toolName: String,
                                     outcome: ToolOutcome) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = AgentKeychain.read() else { throw ClaudeAgentError.notConfigured }
                    let system = DaemonPersona.systemPrompt(digest: "(no necesario)", ecosystem: "(ver resultado)") + """

                    Ahora redacta tu respuesta a Neo usando EXCLUSIVAMENTE el resultado de la herramienta que te paso.                     Conversacional, breve (2–6 frases), en primera persona, con **negritas** para cifras clave.                     Menciona la evidencia (verificado/parcial/no verificado). No repitas tablas: la interfaz ya las muestra debajo.                     Si tiene sentido, termina con una pregunta o un siguiente paso concreto.
                    """
                    var messages: [[String: Any]] = history.suffix(6).map { ["role": $0.role, "content": $0.text.isEmpty ? "…" : $0.text] }
                    while let first = messages.first, first["role"] as? String != "user" { messages.removeFirst() }
                    messages.append(["role": "user", "content": "\(question)\n\n[resultado de \(toolName), evidencia \(outcome.evidence.label)]\n\(String(outcome.digest.prefix(5000)))"])
                    let body: [String: Any] = ["model": AgentSettings.model, "max_tokens": 600, "stream": true, "system": system, "messages": messages]
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 60)
                    request.httpMethod = "POST"
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await NetworkProbe.session.bytes(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard code == 200 else { throw ClaudeAgentError.http(code, "stream") }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if event["type"] as? String == "content_block_delta",
                           let delta = event["delta"] as? [String: Any], let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
