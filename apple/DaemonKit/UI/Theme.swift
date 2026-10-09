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
#endif
