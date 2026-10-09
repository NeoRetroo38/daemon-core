#if os(macOS)
import SwiftUI

extension DaemonPalette {
    public static let ink = Color(white: 0.92)
    public static let dim = Color(white: 0.55)
    public static let faint = Color(white: 0.28)
    public static let grid = Color(white: 0.11)
    public static let amber = Color(red: 1, green: 0.72, blue: 0.18)
    public static let red = Color(red: 1, green: 0.27, blue: 0.23)
    public static let cyan = Color(red: 0.35, green: 0.86, blue: 1)
    /// Tinta manga: el lila de las referencias (cockpit, carrera, riso).
    public static let violet = Color(red: 0.72, green: 0.6, blue: 1)
    public static let plum = Color(red: 0.36, green: 0.22, blue: 0.55)
    /// Papel riso para momentos editoriales puntuales.
    public static let cream = Color(red: 0.93, green: 0.9, blue: 0.79)

    public static func color(_ evidence: Evidence) -> Color {
        switch evidence {
        case .verified: green
        case .partial: amber
        case .unverified: dim
        case .failed: red
        }
    }

    public static func color(_ level: AlertLevel) -> Color {
        switch level { case .info: cyan; case .warning: amber; case .critical: red }
    }
}

public enum DaemonFont {
    public static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    public static let mono = Font.system(size: 12, design: .monospaced)
    public static let monoSmall = Font.system(size: 11, design: .monospaced)
    public static let title = Font.system(size: 28, weight: .ultraLight)
    public static let heading = Font.system(size: 15, weight: .regular)
}

/// Etiqueta de sección estilo instrumento: código en mayúsculas + regla fina.
public struct SectionHeader: View {
    let code: String
    let title: String?
    let trailing: String?

    public init(_ code: String, _ title: String? = nil, trailing: String? = nil) {
        self.code = code
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(code).font(DaemonFont.label).tracking(1.6).foregroundStyle(DaemonPalette.green)
            if let title { Text(title).font(DaemonFont.heading).foregroundStyle(DaemonPalette.ink) }
            Rectangle().fill(DaemonPalette.line).frame(height: 1).frame(maxWidth: .infinity).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            if let trailing { Text(trailing).font(DaemonFont.label).foregroundStyle(DaemonPalette.dim) }
        }
    }
}

public struct EvidenceTag: View {
    let evidence: Evidence
    public init(_ evidence: Evidence) { self.evidence = evidence }
    public var body: some View {
        HStack(spacing: 5) {
            Circle().fill(DaemonPalette.color(evidence)).frame(width: 6, height: 6)
                .shadow(color: evidence == .verified ? DaemonPalette.green.opacity(0.8) : .clear, radius: 3)
            Text(evidence.label.uppercased()).font(DaemonFont.label).tracking(0.8)
        }
        .foregroundStyle(DaemonPalette.color(evidence))
    }
}

public struct StatusDot: View {
    let evidence: Evidence
    var size: CGFloat = 7
    public init(_ evidence: Evidence, size: CGFloat = 7) { self.evidence = evidence; self.size = size }
    public var body: some View {
        Circle().fill(DaemonPalette.color(evidence)).frame(width: size, height: size)
            .shadow(color: DaemonPalette.color(evidence).opacity(evidence == .verified ? 0.9 : 0.3), radius: evidence == .verified ? 4 : 1)
    }
}

/// Panel de instrumento: fondo levemente elevado y filete de 1 px.
public struct InstrumentPanel: ViewModifier {
    var padding: CGFloat = 16
    public func body(content: Content) -> some View {
        content.padding(padding)
            .background(DaemonPalette.panel)
            .overlay(Rectangle().stroke(DaemonPalette.line, lineWidth: 1))
    }
}

extension View {
    public func instrumentPanel(padding: CGFloat = 16) -> some View { modifier(InstrumentPanel(padding: padding)) }
}

public struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = DaemonPalette.ink
    public init(_ key: String, _ value: String, color: Color = DaemonPalette.ink) { self.key = key; self.value = value; self.valueColor = color }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key.uppercased()).font(DaemonFont.label).tracking(0.8).foregroundStyle(DaemonPalette.dim)
            Spacer(minLength: 12)
            Text(value).font(DaemonFont.mono).foregroundStyle(valueColor).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

/// Lectura grande de un valor medido, con su procedencia en el tooltip.
public struct Readout: View {
    let metric: Metric
    public init(_ metric: Metric) { self.metric = metric }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.label.uppercased()).font(DaemonFont.label).tracking(1).foregroundStyle(DaemonPalette.dim).lineLimit(1)
            Text(metric.display).font(.system(size: 17, weight: .light, design: .monospaced))
                .foregroundStyle(metric.evidence == .verified ? DaemonPalette.ink : DaemonPalette.color(metric.evidence)).lineLimit(2)
            HStack(spacing: 6) {
                StatusDot(metric.evidence, size: 5)
                Text(metric.provenance.source).font(.system(size: 9, design: .monospaced)).foregroundStyle(DaemonPalette.faint).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(Rectangle().stroke(DaemonPalette.line, lineWidth: 1))
        .help("\(metric.label): \(metric.display)\nFuente: \(metric.provenance.source)\nMétodo: \(metric.provenance.method)\nObservado: \(DaemonClock.iso(metric.provenance.observedAt))\nEvidencia: \(metric.evidence.label)")
    }
}

/// Fondo de rejilla tenue (instrumentación / papel milimetrado).
public struct GridBackdrop: View {
    var spacing: CGFloat = 24
    public init(spacing: CGFloat = 24) { self.spacing = spacing }
    public var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.width, by: spacing).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0, through: size.height, by: spacing).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(path, with: .color(DaemonPalette.grid), lineWidth: 0.5)
        }
    }
}


// MARK: - Personalidad visual: imprenta, manga y CRT

/// Titular con desregistro riso: dos tintas (verde y lila) desplazadas bajo
/// el blanco. Mantiene la tipografía limpia y le añade grano de imprenta.
public struct RisoTitle: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight
    public init(_ text: String, size: CGFloat = 34, weight: Font.Weight = .light) {
        self.text = text
        self.size = size
        self.weight = weight
    }
    public var body: some View {
        let font = Font.system(size: size, weight: weight)
        ZStack(alignment: .leading) {
            Text(text).font(font).foregroundStyle(DaemonPalette.violet.opacity(0.75)).offset(x: 2.2, y: 1.4).blendMode(.screen)
            Text(text).font(font).foregroundStyle(DaemonPalette.green.opacity(0.55)).offset(x: -1.4, y: -0.8).blendMode(.screen)
            Text(text).font(font).foregroundStyle(Color.white)
        }
        .compositingGroup()
        .tracking(-0.6)
    }
}

/// Rótulo editorial «02 — AGENTE».
public struct EditorialLabel: View {
    let number: String
    let title: String
    public init(_ number: String, _ title: String) { self.number = number; self.title = title }
    public var body: some View {
        HStack(spacing: 8) {
            Text(number).foregroundStyle(DaemonPalette.green)
            Rectangle().fill(DaemonPalette.green).frame(width: 18, height: 1)
            Text(title.uppercased()).foregroundStyle(DaemonPalette.dim)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.4)
    }
}

/// Marco con esquinas en L verdes (como el visor del Cubo en la web).
public struct CornerBrackets: ViewModifier {
    var color: Color = DaemonPalette.green
    var length: CGFloat = 14
    public func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                let w = geometry.size.width, h = geometry.size.height, l = length
                Path { path in
                    path.move(to: CGPoint(x: 0, y: l)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: l, y: 0))
                    path.move(to: CGPoint(x: w - l, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: l))
                    path.move(to: CGPoint(x: w, y: h - l)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - l, y: h))
                    path.move(to: CGPoint(x: l, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - l))
                }
                .stroke(color, lineWidth: 1.2)
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    public func cornerBrackets(_ color: Color = DaemonPalette.green, length: CGFloat = 14) -> some View {
        modifier(CornerBrackets(color: color, length: length))
    }
}

/// Trama de semitono (manga/riso): puntos cuyo radio cae hacia un foco.
public struct Halftone: View {
    var color: Color
    var spacing: CGFloat
    var focus: UnitPoint
    public init(color: Color = DaemonPalette.violet, spacing: CGFloat = 7, focus: UnitPoint = .topTrailing) {
        self.color = color
        self.spacing = spacing
        self.focus = focus
    }
    public var body: some View {
        Canvas { context, size in
            let fx = focus.x * size.width, fy = focus.y * size.height
            let reach = hypot(size.width, size.height) * 0.7
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : spacing / 2
                while x < size.width {
                    let d = hypot(x - fx, y - fy) / reach
                    let r = max(0, (1 - d)) * spacing * 0.42
                    if r > 0.25 { context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color)) }
                    x += spacing
                }
                y += spacing * 0.866
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Grano de imprenta estático (generado una vez, determinista).
public struct PaperGrain: View {
    var opacity: Double
    public init(opacity: Double = 0.06) { self.opacity = opacity }
    static let image: Image = {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt64 = 0x5CE7A2
        for index in 0..<(size * size) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8(truncatingIfNeeded: seed >> 56)
            pixels[index * 4] = 255; pixels[index * 4 + 1] = 255; pixels[index * 4 + 2] = 255
            pixels[index * 4 + 3] = value > 200 ? value / 2 : 0
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return Image(decorative: cg, scale: 2)
    }()
    public var body: some View {
        Rectangle().fill(ImagePaint(image: Self.image, scale: 1)).opacity(opacity).allowsHitTesting(false).blendMode(.screen)
    }
}

/// Líneas de exploración CRT.
public struct Scanlines: View {
    var opacity: Double
    public init(opacity: Double = 0.08) { self.opacity = opacity }
    public var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.height, by: 3).forEach { y in path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
            context.fill(path, with: .color(Color.black.opacity(opacity * 4)))
        }
        .allowsHitTesting(false)
    }
}

/// Líneas cinéticas de manga: aparecen cuando Daemon está midiendo.
public struct SpeedLines: View {
    let active: Bool
    var color: Color
    public init(active: Bool, color: Color = DaemonPalette.green) { self.active = active; self.color = color }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !active)) { timeline in
            Canvas { context, size in
                guard active else { return }
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let radius = hypot(size.width, size.height) * 0.6
                var generator = UInt64(Int(t * 12))
                for index in 0..<56 {
                    generator = generator &* 2862933555777941757 &+ 3037000493
                    let jitter = Double(generator >> 40) / Double(1 << 24)
                    let angle = Double(index) / 56 * .pi * 2 + jitter * 0.08
                    let inner = radius * (0.55 + jitter * 0.25)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                    context.stroke(path, with: .color(color.opacity(0.10 + jitter * 0.12)), lineWidth: 0.6 + jitter * 1.4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
