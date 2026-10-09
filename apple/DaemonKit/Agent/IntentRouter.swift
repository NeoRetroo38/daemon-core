import Foundation

/// Traduce una petición en español a una llamada de herramienta declarada.
/// Determinista, local y sin tokens: el LLM solo entra cuando no hay intención.
public struct RoutedIntent: Sendable, Equatable {
    public let tool: String
    public let arguments: [String: String]
    /// Neo lo pidió de forma explícita (verbo imperativo): cuenta como aprobación
    /// para herramientas no destructivas.
    public let explicitCommand: Bool
}

public enum IntentRouter {
    public static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }

    static func has(_ text: String, _ words: String...) -> Bool { words.contains { text.contains($0) } }

    static func port(in text: String) -> String? {
        guard let range = text.range(of: #"(?<![\d.])\d{2,5}(?![\d.])"#, options: .regularExpression) else { return nil }
        let value = String(text[range])
        guard let number = Int(value), (1...65535).contains(number) else { return nil }
        return value
    }

    public static func repository(in text: String, names: [String]) -> String? {
        let folded = fold(text)
        // El nombre más largo gana (daemon-core antes que daemon).
        if let exact = names.sorted(by: { $0.count > $1.count }).first(where: { folded.contains(fold($0)) }) { return exact }
        let aliases = ["daemon": "daemon-core", "landing": "scenarys", "neos-cube": "cubo-de-neo", "motor": "cubo-de-neo"]
        return aliases.first { folded.contains($0.key) && names.contains($0.value) }?.value
    }

    public static func route(_ raw: String, repositories: [String]) -> RoutedIntent? {
        let text = fold(raw)
        let repo = repository(in: raw, names: repositories)
        var args: [String: String] = [:]
        if let repo { args["repo"] = repo }
        let imperative = has(text, "ejecuta", "lanza", "corre", "pasa los", "compila", "instala", "abre", "cierra", "comprueba", "levanta", "para ", "deten", "run ")
        func intent(_ tool: String, _ extra: [String: String] = [:]) -> RoutedIntent {
            RoutedIntent(tool: tool, arguments: args.merging(extra) { $1 }, explicitCommand: imperative)
        }

        if has(text, "tunel") { return intent(has(text, "cierra", "para", "deten", "close") ? "cube.tunnel.close" : "cube.tunnel.open") }
        if has(text, "compila", "build") && (has(text, "daemon") || repo == "daemon-core" || repo == nil) && !has(text, "test") { return intent("daemon.build") }
        if has(text, "instala") && !has(text, "instalad") { return intent("daemon.install") }
        if has(text, "test", "prueba") && imperative { return intent("repo.tests", repo == nil ? ["repo": "daemon-core"] : [:]) }
        if has(text, "deten", "para el servicio", "mata"), let port = port(in: text) { return intent("service.stop", ["port": port]) }
        if has(text, "puerto") && port(in: text) == nil {
            let declared: [(String, String)] = [("api", "3000"), ("frontend", "8081"), ("web", "8081"), ("landing", "5173"), ("cubo", "8765"), ("motor", "8765")]
            if let match = declared.first(where: { text.contains($0.0) }) { return intent("system.ports", ["port": match.1]) }
        }
        if has(text, "puerto", "proceso", "escucha", "listener") || (port(in: text) != nil && has(text, "usa", "quien", "que hay")) {
            return intent("system.ports", port(in: text).map { ["port": $0] } ?? [:])
        }
        if has(text, "neon", "postgres", "base de datos") { return intent("neon.health") }
        if has(text, "ruta", "frontend", "recorrido") && !has(text, "cubo 3d") { return intent("choisys.health") }
        if has(text, "usuario") { return intent("choisys.users") }
        if has(text, "cubo", "motor", "8765") && !has(text, "3d", "metric", "visual", "dibuja") { return intent("cube.health") }
        if has(text, "choisys") && !has(text, "diff", "pr", "commit", "test", "metric", "cambio") && repo != nil && !has(text, "abre") {
            return intent("choisys.health")
        }
        if has(text, "tailnet", "tailscale", "red privada", "peers", "nodos") { return intent("network.tailnet") }
        if has(text, "desktop", "pc ") && !has(text, "cubo") { return intent("network.tailnet") }
        if has(text, "pull request") || text.range(of: #"\bprs?\b"#, options: .regularExpression) != nil { return intent("github.prs") }
        if has(text, "action", "workflow", " ci", "pipeline") { return intent("github.actions") }
        if has(text, "issue") { return intent("github.issues") }
        if has(text, "diff") { return intent("repo.diff") }
        if has(text, "abre") && repo != nil { return intent("repo.open") }
        if has(text, "hoy", "cambiado", "ha pasado", "timeline", "commits") { return intent("repo.timeline", has(text, "hoy") ? ["since": "today"] : [:]) }
        if has(text, "3d", "cubo de metricas", "visualiza", "dibuja") { return intent("repo.cube") }
        if has(text, "metrica", "lineas", "tamano", "lenguaje", "cuanto codigo") && repo != nil { return intent("repo.metrics") }
        if has(text, "cambios", "dirty", "que repos", "repositorios", "estado de los repos", "sin commit") && repo == nil { return intent("repo.list") }
        if has(text, "estado", "como esta", "como va") && repo != nil { return intent("repo.status") }
        if has(text, "cpu", "ram", "memoria", "disco", "bateria", "temperatura", "recursos", "uptime", "el mac", "sistema") { return intent("system.resources") }
        if has(text, "herramienta", "toolchain", "instalado", "version", "tecnolog", "licencia") { return intent("toolchain.inventory") }
        if has(text, "topolog", "mapa", "ecosistema", "todo", "servicios", "salud") { return intent(has(text, "servicio", "salud") ? "service.health" : "network.topology") }
        if has(text, "latencia") { return intent("service.health") }
        if repo != nil { return intent("repo.status") }
        return nil
    }
}
