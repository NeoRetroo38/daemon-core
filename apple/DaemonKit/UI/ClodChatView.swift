#if os(macOS)
import AppKit
import SwiftUI

/// Sala de Clod: Neo, Clod (Claude) y Daemon en el mismo hilo.
public struct ClodChatView: View {
    @ObservedObject var clod: ClodSession
    let config: TopologyConfig
    let liveServices: (String) -> Int?
    @State private var input = ""
    @FocusState private var focused: Bool

    public init(clod: ClodSession, config: TopologyConfig, liveServices: @escaping (String) -> Int?) {
        self.clod = clod
        self.config = config
        self.liveServices = liveServices
    }

    static let suggestions = ["¿Qué recuerdas de Daemon y de mí?", "@daemon ¿cómo está choisys?", "¿Qué quedó pendiente en la última sesión?",
                              "Anota que el Cubo solo se consume por túnel", "@claude revisa el buzón y prepara la PR"]

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(DaemonPalette.line).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if clod.messages.isEmpty { welcome }
                            ForEach(clod.messages) { message in
                                MessageRow(message: message, perform: { clod.perform($0) }, config: config, liveServices: liveServices).id(message.id)
                            }
                        }
                        .padding(.horizontal, 28).padding(.vertical, 22)
                    }
                    .onChange(of: clod.messages.count) { _, _ in
                        if let last = clod.messages.last?.id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) } }
                    }
                }
                Rectangle().fill(DaemonPalette.line).frame(height: 1)
                composer
            }
            Rectangle().fill(DaemonPalette.line).frame(width: 1)
            memoryPanel.frame(width: 300)
        }
        .background(Color.black)
    }

    var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(DaemonPalette.violet, lineWidth: 1).frame(width: 24, height: 24)
                Text("C").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(DaemonPalette.violet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CLOD").font(.system(size: 15, weight: .light, design: .monospaced)).tracking(4)
                Text(ClodPersona.tagline).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim)
            }
            Spacer()
            Text(clod.connected ? "CLAUDE · \(ClodSession.model.uppercased())" : "SIN API KEY · BUZÓN ACTIVO").font(DaemonFont.label).tracking(1)
                .foregroundStyle(clod.connected ? DaemonPalette.violet : DaemonPalette.amber)
            Button { clod.clear() } label: { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(DaemonPalette.dim).help("Vaciar la sala (la memoria en disco se conserva)")
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(SpeedLines(active: clod.busy, color: DaemonPalette.violet))
    }

    var welcome: some View {
        ZStack(alignment: .topTrailing) {
            Halftone(color: DaemonPalette.plum, spacing: 8, focus: .topTrailing).frame(height: 260).opacity(0.7)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
            VStack(alignment: .leading, spacing: 14) {
                EditorialLabel("03", "Sala de coordinación")
                RisoTitle("No volvemos a empezar.", size: 32)
                Text("Clod es Claude dentro de Daemon. Lee la memoria compartida (clod/MEMORIA.md), la bitácora y el buzón, pregunta a Daemon por datos medidos y deja encargos para la próxima sesión de Claude.")
                    .font(.system(size: 13)).foregroundStyle(DaemonPalette.dim).frame(maxWidth: 620, alignment: .leading)
                Text("«@daemon …» mide al momento · «@claude …» deja un mensaje en el buzón").font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.violet)
                FlowLayout(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { clod.send(suggestion) }
                            .buttonStyle(.plain).font(DaemonFont.monoSmall).foregroundStyle(DaemonPalette.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6).overlay(Rectangle().stroke(DaemonPalette.violet.opacity(0.4)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 30)
        }
    }

    var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("›").font(.system(size: 18, weight: .light, design: .monospaced)).foregroundStyle(DaemonPalette.violet).padding(.bottom, 2)
            TextField("Habla con Clod · @daemon para medir · @claude para el buzón", text: $input, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).lineLimit(1...5)
                .focused($focused).onSubmit(send)
            Button(action: send) {
                Text(clod.busy ? "PENSANDO" : "ENVIAR").font(DaemonFont.label).tracking(1.2)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(Color.black).background(clod.busy ? DaemonPalette.dim : DaemonPalette.violet)
            }
            .buttonStyle(.plain).disabled(clod.busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .onAppear { focused = true }
    }

    func send() {
        let text = input
        input = ""
        SoundBoard.shared.play(.send)
        clod.send(text)
    }

    var memoryPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("MEMORIA", trailing: clod.memory.exists ? "compartida" : "no encontrada")
                Text(clod.memory.root.path).font(DaemonFont.label).foregroundStyle(DaemonPalette.faint).textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("ABRIR MEMORIA") { NSWorkspace.shared.open(clod.memory.memoryURL) }
                    Button("CARPETA") { NSWorkspace.shared.activateFileViewerSelecting([clod.memory.root]) }
                }.buttonStyle(.plain).font(DaemonFont.label).foregroundStyle(DaemonPalette.violet)
                SectionHeader("BITÁCORA")
                Text(clod.memory.recentLog(lines: 14)).font(.system(size: 10, design: .monospaced)).foregroundStyle(DaemonPalette.dim).textSelection(.enabled)
                SectionHeader("BUZÓN", trailing: "\(clod.memory.pendingInbox().count)")
                ForEach(clod.memory.pendingInbox().suffix(8), id: \.self) { url in
                    Text(url.lastPathComponent).font(.system(size: 10, design: .monospaced)).foregroundStyle(DaemonPalette.ink)
                }
                SectionHeader("PROTOCOLO")
                Text("Neo decide · Daemon mide · Clod razona y recuerda · Claude (sesiones) implementa y deja PRs. Todo lo durable se escribe aquí, nunca secretos.")
                    .font(.system(size: 11)).foregroundStyle(DaemonPalette.dim)
            }
            .padding(18)
        }
        .background(DaemonPalette.panel.opacity(0.5))
    }
}
#endif
