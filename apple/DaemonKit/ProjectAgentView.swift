import SwiftUI

public struct AgentMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: String
    public let text: String
}

public enum DaemonAgent {
    public static let name = "Daemon"
    public static let identity = "Observador técnico sereno, directo y verificable. Distingue hechos, hipótesis y decisiones; nunca inventa estado, nunca cambia su personalidad y no escribe en los repositorios desde Daemon."

    public static func reply(to question: String, repository: RepositorySnapshot, insights: RepositoryInsights) -> String {
        let query = question.lowercased()
        let context = "\(repository.name) está en \(repository.branch ?? "rama no verificada"), con \(insights.fileCount) archivos observados y capacidades: \(insights.capabilities.joined(separator: ", "))."
        if query.contains("estado") || query.contains("resumen") { return "Hecho observado: \(context) El árbol de trabajo figura como \(repository.workingTreeLabel.lowercased())." }
        if query.contains("test") || query.contains("prueba") { return "Puedo comprobar estructura, frontend, backend, Cubo y alcance HTTP local desde la pestaña Pruebas. En esta versión no ejecuto comandos ni modifico código." }
        if query.contains("implement") || query.contains("código") { return "Puedo convertir la petición en un cambio propuesto con archivos, riesgos y pruebas. La ejecución queda bloqueada por el modo de solo lectura que has definido para Daemon." }
        if query.contains("3d") || query.contains("blender") { return "El mapa 3D representa la distribución tecnológica del repo. Blender está \(insights.blenderAvailable ? "disponible" : "no detectado") y se reservará para producir assets exportados, no para controlar el runtime." }
        return "Contexto cargado: \(context) Formula una consulta sobre arquitectura, pruebas, riesgos o una implementación; separaré siempre evidencia de propuesta."
    }
}

public struct ProjectAgentView: View {
    public let repository: RepositorySnapshot
    public let insights: RepositoryInsights
    @State private var input = ""
    @State private var messages: [AgentMessage] = []

    public init(repository: RepositorySnapshot, insights: RepositoryInsights) {
        self.repository = repository
        self.insights = insights
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(DaemonPalette.green).frame(width: 10, height: 10).padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(DaemonAgent.name).font(.headline)
                    Text(DaemonAgent.identity).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("SOLO LECTURA").font(.caption2.monospaced()).foregroundStyle(DaemonPalette.green)
            }.padding(16).background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            Text("Contexto de \(repository.name) preparado. Pregunta por el estado, pruebas, arquitectura o una propuesta de implementación.")
                                .foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role).font(.caption2.monospaced()).foregroundStyle(DaemonPalette.green)
                                Text(message.text).textSelection(.enabled)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 10))
                                .id(message.id)
                        }
                    }
                }.onChange(of: messages.count) { _, _ in if let id = messages.last?.id { proxy.scrollTo(id) } }
            }
            HStack {
                TextField("Habla con Daemon sobre este proyecto…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain).padding(12).background(DaemonPalette.panel, in: RoundedRectangle(cornerRadius: 9))
                    .onSubmit(send)
                Button("Enviar", action: send).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        messages.append(AgentMessage(role: "TÚ", text: question))
        input = ""
        messages.append(AgentMessage(role: DaemonAgent.name.uppercased(), text: DaemonAgent.reply(to: question, repository: repository, insights: insights)))
    }
}
