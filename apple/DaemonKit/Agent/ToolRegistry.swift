import Foundation

/// Nivel de acción de una herramienta (sección 18 del master prompt).
public enum ToolRisk: String, Codable, Sendable, CaseIterable {
    case read = "READ", write = "WRITE", service = "SERVICE", network = "NETWORK", destructive = "DESTRUCTIVE"

    public var label: String {
        switch self {
        case .read: "lectura"
        case .write: "escritura"
        case .service: "servicio"
        case .network: "red"
        case .destructive: "destructiva"
        }
    }
}

public struct ToolParameter: Codable, Sendable, Hashable {
    public let name: String
    public let description: String
    public let required: Bool
}

/// Declaración explícita de una herramienta. El agente (local o LLM) solo
/// puede invocar lo que está aquí; nunca una shell libre.
public struct ToolSpec: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let description: String
    public let inputs: [ToolParameter]
    public let outputs: String
    public let risk: ToolRisk
    /// Pide confirmación aunque Neo lo haya solicitado en el chat.
    public let requiresConfirmation: Bool
    public let technology: String
    public var id: String { name }
}

public enum ToolCatalog {
    static func p(_ name: String, _ description: String, required: Bool = false) -> ToolParameter {
        ToolParameter(name: name, description: description, required: required)
    }

    public static let all: [ToolSpec] = [
        .init(name: "repo.list", description: "Catálogo de repositorios con rama, HEAD, estado y sincronía.", inputs: [], outputs: "lista de repos", risk: .read, requiresConfirmation: false, technology: "núcleo C++ · git"),
        .init(name: "repo.status", description: "Estado Git y cambios locales de un repositorio.", inputs: [p("repo", "nombre del repositorio")], outputs: "rama, HEAD, ahead/behind, archivos cambiados", risk: .read, requiresConfirmation: false, technology: "núcleo C++ · git status --porcelain=v2"),
        .init(name: "repo.diff", description: "Resumen del diff de trabajo frente a HEAD.", inputs: [p("repo", "nombre del repositorio", required: true)], outputs: "diff --stat redactado", risk: .read, requiresConfirmation: false, technology: "git diff --stat"),
        .init(name: "repo.metrics", description: "Métricas del índice local: archivos, líneas, lenguajes, tests, commits.", inputs: [p("repo", "nombre del repositorio", required: true)], outputs: "métricas con procedencia", risk: .read, requiresConfirmation: false, technology: "índice local · FileManager · git"),
        .init(name: "repo.timeline", description: "Commits recientes (hoy o últimos) de uno o todos los repos.", inputs: [p("repo", "nombre del repositorio"), p("since", "today | week")], outputs: "línea de tiempo", risk: .read, requiresConfirmation: false, technology: "git log"),
        .init(name: "repo.cube", description: "Cubo 3D de métricas del repositorio.", inputs: [p("repo", "nombre del repositorio", required: true)], outputs: "visualización", risk: .read, requiresConfirmation: false, technology: "SceneKit"),
        .init(name: "repo.open", description: "Abre el repositorio en Finder.", inputs: [p("repo", "nombre del repositorio", required: true)], outputs: "ventana de Finder", risk: .read, requiresConfirmation: false, technology: "NSWorkspace"),
        .init(name: "repo.tests", description: "Ejecuta la batería de tests conocida del repositorio.", inputs: [p("repo", "nombre del repositorio", required: true)], outputs: "resultado y resumen", risk: .write, requiresConfirmation: false, technology: "swift test · ctest · make · npm test"),
        .init(name: "daemon.build", description: "Compila Daemon.app desde daemon-core.", inputs: [], outputs: "ruta del bundle", risk: .write, requiresConfirmation: false, technology: "swiftc · clang++ · scripts/apple-build-macos.sh"),
        .init(name: "daemon.install", description: "Instala la build en /Applications/Daemon.app conservando una copia de la anterior.", inputs: [], outputs: "ruta instalada y copia", risk: .write, requiresConfirmation: true, technology: "ditto · codesign ad-hoc"),
        .init(name: "github.prs", description: "Pull requests del repositorio en GitHub.", inputs: [p("repo", "nombre del repositorio")], outputs: "PRs", risk: .read, requiresConfirmation: false, technology: "GitHub CLI"),
        .init(name: "github.issues", description: "Issues abiertas.", inputs: [p("repo", "nombre del repositorio")], outputs: "issues", risk: .read, requiresConfirmation: false, technology: "GitHub CLI"),
        .init(name: "github.actions", description: "Ejecuciones recientes de GitHub Actions.", inputs: [p("repo", "nombre del repositorio")], outputs: "runs y conclusión", risk: .read, requiresConfirmation: false, technology: "GitHub CLI"),
        .init(name: "system.resources", description: "CPU, memoria, disco, batería, temperatura e interfaces del Mac.", inputs: [], outputs: "métricas del sistema", risk: .read, requiresConfirmation: false, technology: "sysctl · Mach · IOKit · getifaddrs"),
        .init(name: "system.ports", description: "Puertos TCP en escucha, proceso, PID, interfaz, CPU y memoria.", inputs: [p("port", "puerto concreto")], outputs: "listeners", risk: .read, requiresConfirmation: false, technology: "lsof · ps"),
        .init(name: "service.health", description: "Salud de los servicios declarados (Mac, Desktop y externos).", inputs: [p("service", "id del servicio")], outputs: "estado, latencia p50/p95", risk: .read, requiresConfirmation: false, technology: "URLSession · Network.framework"),
        .init(name: "service.stop", description: "Detiene (SIGTERM) el proceso de un servicio de desarrollo en un puerto declarado.", inputs: [p("port", "puerto del servicio", required: true)], outputs: "resultado", risk: .service, requiresConfirmation: true, technology: "kill(2)"),
        .init(name: "network.topology", description: "Mapa del ecosistema: máquinas, servicios y dependencias.", inputs: [], outputs: "topología", risk: .read, requiresConfirmation: false, technology: "Tailscale · lsof · sondas HTTP"),
        .init(name: "network.tailnet", description: "Nodos de la tailnet, presencia e IPs.", inputs: [], outputs: "peers", risk: .read, requiresConfirmation: false, technology: "Tailscale CLI"),
        .init(name: "cube.health", description: "Estado del Cubo de Neo y su contrato de aislamiento 127.0.0.1:8765.", inputs: [], outputs: "salud y exposición", risk: .read, requiresConfirmation: false, technology: "núcleo C++ check_exposure · TCP"),
        .init(name: "cube.tunnel.open", description: "Abre un túnel SSH -N -L 127.0.0.1:8765 → Desktop 127.0.0.1:8765 por la tailnet.", inputs: [], outputs: "PID del túnel", risk: .network, requiresConfirmation: false, technology: "OpenSSH · Tailscale"),
        .init(name: "cube.tunnel.close", description: "Cierra el túnel SSH del Cubo.", inputs: [], outputs: "resultado", risk: .network, requiresConfirmation: false, technology: "kill(2)"),
        .init(name: "choisys.health", description: "Salud de choisys y ruta cliente → frontend → API → DB → Cubo.", inputs: [], outputs: "ruta con el eslabón roto", risk: .read, requiresConfirmation: false, technology: "sondas HTTP · TCP"),
        .init(name: "choisys.users", description: "Nombres visibles de usuarios del almacén local autorizado (sin correo, IDs ni hashes).", inputs: [], outputs: "displayName", risk: .read, requiresConfirmation: false, technology: "proyección mínima JSON"),
        .init(name: "neon.health", description: "Diagnóstico de solo lectura de Neon mediante el script de choisys.", inputs: [], outputs: "conectividad, migraciones, lectura, latencia", risk: .service, requiresConfirmation: false, technology: "Node · Prisma · PostgreSQL"),
        .init(name: "toolchain.inventory", description: "Herramientas instaladas con versión y licencia verificable.", inputs: [], outputs: "inventario", risk: .read, requiresConfirmation: false, technology: "Homebrew · Info.plist · --version"),
    ]

    public static func spec(_ name: String) -> ToolSpec? { all.first { $0.name == name } }
}
