#if os(macOS)
import AppKit
import SwiftUI

/// SFX de Daemon (generados por assets/sfx/generate_sfx.py; sustituibles
/// desde Ableton con el mismo nombre). Volumen bajo y desactivables.
@MainActor
public final class SoundBoard {
    public static let shared = SoundBoard()
    public enum Cue: String, CaseIterable { case boot, measure, verified, partial, alert, send, clod }
    private var sounds: [Cue: NSSound] = [:]

    public var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "daemon.sfx.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "daemon.sfx.enabled") }
    }

    private init() {
        for cue in Cue.allCases {
            guard let url = AssetLocator.url("Sounds/\(cue.rawValue).wav"), let sound = NSSound(contentsOf: url, byReference: true) else { continue }
            sound.volume = cue == .boot ? 0.55 : 0.35
            sounds[cue] = sound
        }
    }

    public var available: Bool { !sounds.isEmpty }

    public func play(_ cue: Cue) {
        guard enabled, let sound = sounds[cue] else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    public func play(for evidence: Evidence) {
        switch evidence {
        case .verified: play(.verified)
        case .partial, .unverified: play(.partial)
        case .failed: play(.alert)
        }
    }
}

/// Localiza recursos en el bundle (Contents/Resources) o, en desarrollo, en
/// `assets/` del repositorio indicado por DAEMON_ASSETS.
public enum AssetLocator {
    public static func url(_ relative: String) -> URL? {
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let dev = ProcessInfo.processInfo.environment["DAEMON_ASSETS"] {
            let mapped = relative.replacingOccurrences(of: "Sounds/", with: "sfx/").replacingOccurrences(of: "VFX/", with: "vfx/boot/")
            let url = URL(fileURLWithPath: dev).appendingPathComponent(mapped)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    public static func bootFrames() -> [NSImage] {
        var frames: [NSImage] = []
        for index in 1...240 {
            guard let url = url(String(format: "VFX/boot_%04d.png", index)), let image = NSImage(contentsOf: url) else { break }
            frames.append(image)
        }
        return frames
    }
}

/// Secuencia de arranque renderizada en Blender + titular riso + SFX.
public struct BootSequence: View {
    let onFinish: () -> Void
    @State private var frames: [NSImage] = []
    @State private var start = Date()
    @State private var finished = false

    public init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    public var body: some View {
        ZStack {
            Color.black
            Halftone(color: DaemonPalette.plum, spacing: 9, focus: .bottomLeading).opacity(0.55)
            Scanlines(opacity: 0.05)
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                let index = min(frames.count - 1, Int(elapsed * 30))
                VStack(spacing: 26) {
                    ZStack {
                        if !frames.isEmpty, index >= 0 {
                            Image(nsImage: frames[index]).resizable().interpolation(.high).frame(width: 300, height: 300)
                                .shadow(color: DaemonPalette.green.opacity(0.35), radius: 14)
                        } else {
                            DaemonSigil(active: true).frame(width: 120, height: 120)
                        }
                    }
                    .frame(width: 320, height: 320)
                    .cornerBrackets(DaemonPalette.green.opacity(min(1, elapsed)), length: 18)
                    VStack(spacing: 8) {
                        RisoTitle("DAEMON", size: 42, weight: .ultraLight).opacity(min(1, max(0, elapsed - 0.9) * 2))
                        Text("control plane · Scenarys · el Cubo mide, Daemon observa, Neo decide")
                            .font(DaemonFont.label).tracking(1.6).foregroundStyle(DaemonPalette.dim)
                            .opacity(min(1, max(0, elapsed - 1.2) * 2))
                    }
                }
                .onChange(of: elapsed > 2.4) { _, done in if done { finish() } }
            }
            PaperGrain(opacity: 0.08)
            VStack { Spacer(); Text("clic para saltar").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint).padding(18) }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            frames = AssetLocator.bootFrames()
            start = Date()
            SoundBoard.shared.play(.boot)
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Barra de transporte (Ableton/Spotify): la monitorización como una pista.
public struct TransportBar: View {
    @Binding var live: Bool
    @Binding var interval: Double
    let observing: Bool
    let latencies: [Int]
    let observations: Int
    let lastObserved: Date?
    let onMeasure: () -> Void
    @State private var sound = SoundBoard.shared.enabled

    public init(live: Binding<Bool>, interval: Binding<Double>, observing: Bool, latencies: [Int], observations: Int, lastObserved: Date?, onMeasure: @escaping () -> Void) {
        self._live = live
        self._interval = interval
        self.observing = observing
        self.latencies = latencies
        self.observations = observations
        self.lastObserved = lastObserved
        self.onMeasure = onMeasure
    }

    public var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                Button { live.toggle() } label: {
                    Image(systemName: live ? "pause.fill" : "play.fill").font(.system(size: 13)).foregroundStyle(Color.black)
                        .frame(width: 30, height: 30).background(Circle().fill(live ? DaemonPalette.green : DaemonPalette.ink))
                }.buttonStyle(.plain).help(live ? "Pausar la monitorización en vivo" : "Reanudar la monitorización en vivo")
                Button(action: onMeasure) { Image(systemName: "record.circle").font(.system(size: 15)) }
                    .buttonStyle(.plain).foregroundStyle(observing ? DaemonPalette.red : DaemonPalette.dim).help("Medir ahora")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(live ? (observing ? "MIDIENDO" : "EN VIVO") : "EN PAUSA").font(DaemonFont.label).tracking(1.6)
                    .foregroundStyle(live ? DaemonPalette.green : DaemonPalette.dim)
                Text(lastObserved.map { "última · \(DaemonClock.relative($0))" } ?? "sin observación").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
            }.frame(width: 120, alignment: .leading)
            Waveform(values: latencies, active: observing).frame(height: 28).frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text("BPM").font(DaemonFont.label).foregroundStyle(DaemonPalette.faint)
                Text(String(format: "%.0f", 60 / interval)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(DaemonPalette.ink)
                Stepper("", value: $interval, in: 5...120, step: 5).labelsHidden().controlSize(.mini)
                    .help("Intervalo entre observaciones: \(Int(interval)) s")
            }
            Text(String(format: "%04d", observations)).font(.system(size: 13, design: .monospaced)).foregroundStyle(DaemonPalette.dim).help("Observaciones en esta sesión")
            Button {
                sound.toggle()
                SoundBoard.shared.enabled = sound
                if sound { SoundBoard.shared.play(.verified) }
            } label: { Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash").font(.system(size: 12)) }
                .buttonStyle(.plain).foregroundStyle(sound ? DaemonPalette.violet : DaemonPalette.faint).help("SFX de Daemon")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(DaemonPalette.panel.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(DaemonPalette.line).frame(height: 1) }
    }
}

/// Forma de onda de latencias (p50 por observación), estilo clip de audio.
public struct Waveform: View {
    let values: [Int]
    let active: Bool
    public init(values: [Int], active: Bool) { self.values = values; self.active = active }
    public var body: some View {
        Canvas { context, size in
            let samples = Array(values.suffix(90))
            guard !samples.isEmpty else {
                var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(DaemonPalette.faint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                return
            }
            var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: size.height / 2)); baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(baseline, with: .color(DaemonPalette.grid), lineWidth: 1)
            let maximum = Double(max(samples.max() ?? 1, 1))
            let bar = size.width / 90
            for (index, value) in samples.enumerated() {
                let h = max(2, CGFloat(Double(value) / maximum) * size.height)
                let x = CGFloat(index + 90 - samples.count) * bar
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: max(1, bar - 1), height: h)
                let recent = index == samples.count - 1
                context.fill(Path(rect), with: .color(recent ? (active ? DaemonPalette.green : DaemonPalette.ink) : DaemonPalette.violet.opacity(0.55)))
            }
        }
        .help("Latencia de las sondas (ms) por observación")
    }
}
#endif
