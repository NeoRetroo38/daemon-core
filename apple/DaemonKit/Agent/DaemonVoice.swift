import Foundation

/// Voz local de Daemon: convierte resultados medidos en una respuesta
/// conversacional, sin LLM y sin inventar nada que no esté en el resultado.
public enum DaemonVoice {
    static func pick(_ options: [String], seed: String) -> String {
        let value = seed.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return options[Int(value % UInt32(options.count))]
    }

    static func openers(_ evidence: Evidence) -> [String] {
        switch evidence {
        case .verified: ["Lo acabo de medir.", "Recién comprobado.", "Mirado ahora mismo:", "Esto es lo que veo:", "Medido, no supuesto:"]
        case .partial: ["Tengo una parte medida y otra no, te lo separo.", "Evidencia parcial:", "Medio verificado, ojo:"]
        case .unverified: ["Aquí no tengo una medida fiable.", "No lo he podido verificar todavía.", "Sin evidencia suficiente:"]
        case .failed: ["Algo no responde.", "Hay un fallo:", "Tenemos un problema:"]
        }
    }

    public static func compose(question: String, tool: String?, outcome: ToolOutcome, proposal: ToolSpec? = nil) -> String {
        if let proposal {
            let level = proposal.risk.label
            var text = proposal.requiresConfirmation
                ? "Puedo hacerlo, pero es una acción de **\(level)** y prefiero que la confirmes tú: \(proposal.description.lowercased())"
                : "Puedo encargarme (**\(level)**). Como no me lo has pedido como orden, te dejo el botón: \(proposal.description.lowercased())"
            if !outcome.text.isEmpty { text += "\n\nPor si te sirve, \(outcome.text)." }
            return text
        }
        let opener = pick(openers(outcome.evidence), seed: question)
        var body = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        body = emphasize(body)
        var parts = ["\(opener) \(body)"]
        if let closer = closer(tool: tool, outcome: outcome, seed: question) { parts.append(closer) }
        return parts.joined(separator: "\n\n")
    }

    /// Resalta cifras y puertos para que la respuesta se lea de un vistazo.
    static func emphasize(_ text: String) -> String {
        var result = text
        for pattern in [#"(?<![\w*]):\d{2,5}\b"#, #"\bHTTP \d{3}\b"#, #"\b\d+(?:[.,]\d+)? ?(?:ms|s|GB|MB|%)\b"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = result as NSString
            var replaced = ""
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                replaced += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                replaced += "**" + ns.substring(with: match.range) + "**"
                cursor = match.range.location + match.range.length
            }
            replaced += ns.substring(from: cursor)
            result = replaced
        }
        return result.replacingOccurrences(of: "****", with: "")
    }

    static func closer(tool: String?, outcome: ToolOutcome, seed: String) -> String? {
        let actions = outcome.blocks.compactMap { block -> [AgentAction]? in if case .actions(let list) = block { return list }; return nil }.flatMap { $0 }
        switch tool {
        case "system.ports":
            return pick(["Si alguno no te cuadra, dime el puerto y te digo de qué repo es o lo paro.",
                         "¿Quieres que pare alguno de los de desarrollo?"], seed: seed)
        case "cube.health":
            return actions.contains { $0.tool == "cube.tunnel.open" }
                ? "Si quieres usar el Cubo del Desktop desde aquí, abro el túnel cifrado; nada se publica en la red."
                : nil
        case "choisys.health":
            return outcome.text.contains("Neon") || actions.contains { $0.tool == "neon.health" }
                ? "Neon no lo mido solo: dime «comprueba Neon» y lanzo el diagnóstico de solo lectura." : nil
        case "repo.status":
            return actions.isEmpty ? nil : "¿Te enseño el diff o lanzo los tests?"
        case "repo.list":
            return pick(["Pregúntame por cualquiera y entro en detalle.", "¿Por cuál empezamos?"], seed: seed)
        case "network.tailnet":
            return "Si necesitas llegar a un servicio del Desktop, dime cuál y lo sondeo."
        case "repo.tests":
            return outcome.evidence == .verified ? "Todo en verde. ¿Compilo e instalo?" : "¿Miramos juntos el fallo?"
        case nil:
            return "No he reconocido una herramienta para esto, así que te doy lo que sí sé medido. Pregúntame por repos, puertos, red, choisys, Neon o el Cubo."
        default:
            return nil
        }
    }
}
