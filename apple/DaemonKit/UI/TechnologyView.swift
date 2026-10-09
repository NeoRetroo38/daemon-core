import Foundation
#if os(macOS)
import SwiftUI
#endif

/// Qué tecnología sustenta cada función de Daemon. La versión y la licencia
/// solo se rellenan desde fuentes locales verificables; lo demás queda como
/// «no verificado».
public struct TechnologyEntry: Identifiable, Sendable, Hashable {
    public let technology: String
    public let usage: String
    public let component: String
    public let repository: String
    public let origin: String
    /// Nombre en el inventario de herramientas (para versión/licencia).
    public let toolchainName: String?
    public var id: String { technology + component }
}

public enum TechnologyRegistry {
    public static let entries: [TechnologyEntry] = [
        .init(technology: "SwiftUI", usage: "interfaz nativa, mapa vivo, chat", component: "DaemonKit/UI · DaemonMac", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Swift"),
        .init(technology: "SceneKit", usage: "cubo 3D de métricas con selección", component: "UI/MetricCube.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "Network.framework", usage: "sondas TCP (exposición del Cubo)", component: "Control/NetworkProbe.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "URLSession", usage: "health HTTP efímero, API de Claude opcional", component: "Control/NetworkProbe.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "IOKit · Mach · sysctl", usage: "batería, memoria, CPU del Mac", component: "Control/SystemProbe.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "Security (Llavero)", usage: "API key opcional, nunca en disco", component: "Agent/ClaudeAgent.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "CryptoKit", usage: "huellas SHA-256 del índice local", component: "Control/RepositoryIndex.swift", repository: "daemon-core", origin: "macOS SDK", toolchainName: "Xcode"),
        .init(technology: "C++20 (clang, libc++)", usage: "núcleo: política de comandos, Git, exposición, redacción", component: "src/daemon · adapters", repository: "daemon-core", origin: "Xcode toolchain", toolchainName: "clang"),
        .init(technology: "Git", usage: "estado, historia y diff de repos", component: "adapters/git_adapter.cpp · GitInsights", repository: "daemon-core", origin: "/usr/bin/git", toolchainName: "Git"),
        .init(technology: "GitHub CLI", usage: "PRs, issues y Actions", component: "Control/GitHubProbe.swift", repository: "daemon-core", origin: "Homebrew", toolchainName: "GitHub CLI"),
        .init(technology: "lsof · ps", usage: "puertos en escucha y procesos", component: "Control/PortProbe.swift", repository: "daemon-core", origin: "macOS", toolchainName: nil),
        .init(technology: "Tailscale", usage: "tailnet privada Mac ↔ Desktop ↔ iPhone", component: "Control/TailnetProbe.swift", repository: "daemon-core", origin: "Tailscale.app", toolchainName: "Tailscale"),
        .init(technology: "OpenSSH", usage: "túnel -N -L 127.0.0.1:8765 al Cubo", component: "Agent/ToolExecutor.swift (CubeTunnel)", repository: "daemon-core", origin: "macOS", toolchainName: "OpenSSH"),
        .init(technology: "Node · npm", usage: "diagnóstico Neon (choisys check:neon)", component: "Control/Ecosystem.swift", repository: "choisys", origin: "Homebrew", toolchainName: "Node"),
        .init(technology: "Prisma · PostgreSQL (Neon)", usage: "base de datos de choisys", component: "choisys/apps/api", repository: "choisys", origin: "npm", toolchainName: nil),
        .init(technology: "Express 5", usage: "API de choisys (:3000)", component: "choisys/apps/api", repository: "choisys", origin: "npm", toolchainName: nil),
        .init(technology: "Expo · React Native Web", usage: "frontend de choisys (:8081)", component: "choisys/apps/mobile", repository: "choisys", origin: "npm", toolchainName: nil),
        .init(technology: "Vite · React", usage: "landing de Scenarys (:5173)", component: "scenarys", repository: "scenarys", origin: "npm", toolchainName: nil),
        .init(technology: "C++17 (Cubo de Neo)", usage: "motor privado 127.0.0.1:8765", component: "src/core · src/api", repository: "cubo-de-neo", origin: "repositorio", toolchainName: "clang"),
        .init(technology: "CMake · ctest", usage: "tests del núcleo C++", component: "CMakeLists.txt", repository: "daemon-core", origin: "Homebrew", toolchainName: "CMake"),
        .init(technology: "Claude API (opcional)", usage: "razonamiento con tool use solo de lectura", component: "Agent/ClaudeAgent.swift", repository: "daemon-core", origin: "api.anthropic.com", toolchainName: nil),
        .init(technology: "Blender", usage: "assets 3D exportados, no runtime", component: "pipeline creativo", repository: "—", origin: "Blender.app", toolchainName: "Blender"),
        .init(technology: "Ableton Live Lite", usage: "experimentos audio-reactivos, no runtime", component: "pipeline creativo", repository: "—", origin: "Ableton Live 12 Lite.app", toolchainName: "Ableton Live Lite"),
    ]
}

#if os(macOS)
public struct TechnologyTable: View {
    let tools: [ToolInfo]
    var registry: Bool = false
    public init(tools: [ToolInfo], registry: Bool = false) { self.tools = tools; self.registry = registry }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if registry {
                header(["TECNOLOGÍA", "VERSIÓN", "LICENCIA", "USO EN DAEMON", "COMPONENTE", "REPOSITORIO", "ORIGEN", "ESTADO"])
                ForEach(TechnologyRegistry.entries) { entry in
                    let tool = entry.toolchainName.flatMap { name in tools.first { $0.name == name } }
                    row([entry.technology, tool?.version ?? "no verificado", tool?.license ?? "no verificado", entry.usage, entry.component, entry.repository, entry.origin],
                        evidence: tool?.evidence ?? .unverified,
                        help: tool.map { "Versión: \($0.provenance.method)\nLicencia: \($0.licenseSource ?? "sin fuente local verificable")\nRuta: \($0.path ?? "—")" } ?? "Sin fuente local de versión o licencia: no verificado.")
                }
            } else {
                header(["HERRAMIENTA", "VERSIÓN", "LICENCIA", "USO", "CATEGORÍA", "RUTA", "MÉTODO", "ESTADO"])
                ForEach(tools) { tool in
                    row([tool.name, tool.version ?? "no verificado", tool.license ?? "no verificado", tool.purpose, tool.category, tool.path ?? "no encontrado", tool.provenance.method],
                        evidence: tool.evidence, help: tool.licenseSource ?? "Licencia sin fuente local verificable")
                }
            }
        }
    }

    func header(_ titles: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(titles, id: \.self) { Text($0).font(DaemonFont.label).tracking(0.6).foregroundStyle(DaemonPalette.faint).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(.vertical, 6)
    }

    func row(_ values: [String], evidence: Evidence, help: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Text(value).font(index == 0 ? .system(size: 12, weight: .medium) : DaemonFont.monoSmall)
                        .foregroundStyle(value == "no verificado" ? DaemonPalette.dim : (index == 0 ? DaemonPalette.ink : DaemonPalette.ink.opacity(0.85)))
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                EvidenceTag(evidence).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6).help(help)
            Rectangle().fill(DaemonPalette.grid).frame(height: 1)
        }
    }
}
#endif
