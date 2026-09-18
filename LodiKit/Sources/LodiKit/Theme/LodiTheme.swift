import SwiftUI

// The identity comes from the logo: four saturated primaries on black, sampled
// from the mark itself (see docs/plan.md, "One design system"). These hex values
// live here once — never as a literal in a view — so every tool and every future
// target reads the same numbers.
public enum LodiPalette {
    public static let blue   = Color(lodiHex: 0x026BFD) // the L
    public static let yellow = Color(lodiHex: 0xFED606) // the O
    public static let red    = Color(lodiHex: 0xFC1E26) // the D
    public static let green  = Color(lodiHex: 0x12DE3F) // the I
    public static let ink    = Color(lodiHex: 0x000000) // the ground
    public static let paper  = Color(lodiHex: 0xFFFFFF) // STUDIOS
    /// Not in the logo. The site's pink, kept for exactly one job: the Assistant.
    /// It must never appear in a tool's working area or the sidebar.
    public static let pink   = Color(lodiHex: 0xFF4FA0)

    /// Status is not brand. A separate, slightly desaturated trio — deliberately
    /// none of the four primaries — so a red glow never reads as "you are in
    /// Infrastructure Pro" (docs/ui-review.md, gap 4). Shape and word carry status
    /// first; these only reinforce it, and only ever in content.
    public static let statusOk   = Color(lodiHex: 0x3FB56B)
    public static let statusWarn = Color(lodiHex: 0xE0A030)
    public static let statusFail = Color(lodiHex: 0xD1524E)
}

/// The five tools that are one app. Each owns exactly one logo primary so colour
/// is wayfinding: you know which tool you are in peripherally, before reading a
/// word. The Assistant is deliberately *not* here — it crosses every tool and so
/// carries pink (`LodiTheme.assistantAccent`), off the logo's palette on purpose.
public enum LodiTool: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case webPro
    case appPro
    case infrastructurePro
    case admin

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .terminal:          "LodiTerminal"
        case .webPro:            "WebPro"
        case .appPro:            "AppPro"
        case .infrastructurePro: "Infrastructure Pro"
        case .admin:             "LodiAdmin"
        }
    }

    /// One primary per tool. LodiAdmin is white on black by design.
    public var accent: Color {
        switch self {
        case .terminal:          LodiPalette.green
        case .webPro:            LodiPalette.blue
        case .appPro:            LodiPalette.yellow
        case .infrastructurePro: LodiPalette.red
        case .admin:             LodiPalette.paper
        }
    }

    public var systemImage: String {
        switch self {
        case .terminal:          "terminal"
        case .webPro:            "globe"
        case .appPro:            "square.stack.3d.up"
        case .infrastructurePro: "server.rack"
        case .admin:             "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

/// Semantic entry points for the design system. Black is the ground and white is
/// nearly all the text — exactly the ratio in the mark; the primaries only point.
public enum LodiTheme {
    public static let ground: Color = LodiPalette.ink
    public static let text: Color = LodiPalette.paper
    public static let secondaryText: Color = LodiPalette.paper.opacity(0.6)

    /// The one surface that crosses every tool. Pink lives here and nowhere else.
    public static let assistantAccent: Color = LodiPalette.pink

    /// Status lives in content; tool accents live in chrome; never the same
    /// colour. Pair these with a shape and a word (● ok, ▲ warn, ✕ fail).
    public static let statusOk:   Color = LodiPalette.statusOk
    public static let statusWarn: Color = LodiPalette.statusWarn
    public static let statusFail: Color = LodiPalette.statusFail
}

// MARK: - Per-tool accent through the environment

public struct LodiAccentKey: EnvironmentKey {
    public static let defaultValue: Color = LodiPalette.paper
}

public extension EnvironmentValues {
    /// The accent of the tool the current view belongs to. Read this instead of a
    /// hex literal: `@Environment(\.lodiAccent) private var accent`.
    var lodiAccent: Color {
        get { self[LodiAccentKey.self] }
        set { self[LodiAccentKey.self] = newValue }
    }
}

public extension View {
    /// Enter a tool's working area: sets the semantic accent and the SwiftUI tint
    /// so controls inherit the right colour without a literal in the view.
    func lodiTool(_ tool: LodiTool) -> some View {
        environment(\.lodiAccent, tool.accent)
            .tint(tool.accent)
    }

    /// Enter the Assistant panel, which carries pink and nothing else does.
    func lodiAssistant() -> some View {
        environment(\.lodiAccent, LodiTheme.assistantAccent)
            .tint(LodiTheme.assistantAccent)
    }
}

// MARK: - Hex convenience (internal; the palette is the only caller)

extension Color {
    init(lodiHex hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
