import SwiftUI

/// The colours the apps are drawn from, as one value per appearance.
///
/// Tokens rather than an asset catalogue because this package is shared by
/// three targets — the iOS app, its widgets and the macOS menu bar — and a
/// catalogue would have to be duplicated into each bundle. A struct chosen by
/// `colorScheme` also means a widget can pick the same palette without any of
/// SwiftUI's environment-dependent colour resolution.
///
/// Dark is the designed appearance and light is a real mapping of it, not an
/// inversion: the ladder is canvas → surface → raised, borders are one step off
/// the surface they sit on, and text runs primary → secondary → tertiary.
public struct Palette: Sendable, Equatable {
    /// The flat content background.
    public let canvas: Color
    /// The content surface.
    public let surface: Color
    /// A grouped control or selected segment.
    public let surfaceRaised: Color
    /// Hairlines. Visible, never loud.
    public let border: Color
    /// A hairline that has to be seen — a focused control, a divider under a
    /// sticky header.
    public let borderStrong: Color

    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color

    /// One accent, used for interaction and for nothing else. Status has its
    /// own three colours and must never borrow this one.
    public let accent: Color
    public let accentMuted: Color

    public let positive: Color
    public let warning: Color
    public let negative: Color
    /// Running, queued — work in progress, which is neither good nor bad.
    public let inProgress: Color

    public init(
        canvas: Color,
        surface: Color,
        surfaceRaised: Color,
        border: Color,
        borderStrong: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        accent: Color,
        accentMuted: Color,
        positive: Color,
        warning: Color,
        negative: Color,
        inProgress: Color
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.border = border
        self.borderStrong = borderStrong
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentMuted = accentMuted
        self.positive = positive
        self.warning = warning
        self.negative = negative
        self.inProgress = inProgress
    }

    public static let dark = Palette(
        canvas: Color(hex: 0x101318),
        surface: Color(hex: 0x101318),
        surfaceRaised: Color(hex: 0x1B2028),
        border: Color(hex: 0x303945),
        borderStrong: Color(hex: 0x455163),
        textPrimary: Color(hex: 0xEDF0F4),
        textSecondary: Color(hex: 0xB6BFCC),
        textTertiary: Color(hex: 0xA4AFBE),
        accent: Color(hex: 0x8AB7FF),
        accentMuted: Color(hex: 0x1A2B45),
        positive: Color(hex: 0x7BD4A8),
        warning: Color(hex: 0xEDC477),
        negative: Color(hex: 0xFF929B),
        inProgress: Color(hex: 0x8AB7FF)
    )

    public static let light = Palette(
        canvas: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xF2F4F7),
        border: Color(hex: 0xE0E5EB),
        borderStrong: Color(hex: 0xCBCFD4),
        textPrimary: Color(hex: 0x19202A),
        textSecondary: Color(hex: 0x566170),
        textTertiary: Color(hex: 0x626D7B),
        accent: Color(hex: 0x225ED0),
        accentMuted: Color(hex: 0xEDF2FC),
        positive: Color(hex: 0x24734E),
        warning: Color(hex: 0x86590C),
        negative: Color(hex: 0xB52C36),
        inProgress: Color(hex: 0x2567AD)
    )

    public static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }

    // MARK: Status

    /// One place where a run state becomes a colour, so the row, the bar chart,
    /// the timeline and the widget cannot disagree about what amber means.
    public func color(for status: RunStatus) -> Color {
        switch status {
        case .succeeded: positive
        case .failed: negative
        case .running, .queued: inProgress
        case .awaitingApproval: warning
        case .cancelled, .never: textTertiary
        }
    }

    public func color(for severity: MetricSeverity) -> Color {
        switch severity {
        case .nominal: positive
        case .warning: warning
        case .critical: negative
        }
    }

    public func color(for glyph: GlyphState) -> Color {
        switch glyph {
        case .ok: positive
        case .running: inProgress
        case .failed: negative
        }
    }

    /// Up or down, for a service dot.
    public func color(isUp: Bool) -> Color {
        isUp ? positive : negative
    }

    /// A log level. Info and debug stay in the text ramp rather than taking a
    /// status colour, because almost every line is one of them and a screen
    /// where everything is coloured is a screen where nothing stands out.
    public func color(for level: LogLevel) -> Color {
        switch level {
        case .error: negative
        case .warning: warning
        case .info: textSecondary
        case .debug: textTertiary
        }
    }
}

extension Color {
    /// `0x1B2028` reads like the hex in a design file; three `Double`s divided
    /// by 255 do not.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .dark
}

extension EnvironmentValues {
    /// Read by every view that draws. Set once at the root from `colorScheme`,
    /// and again in each widget, because an extension gets its own environment.
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Applies the palette matching a colour scheme. One call at the root of
    /// each surface is the whole wiring.
    public func homelabPalette(_ scheme: ColorScheme) -> some View {
        environment(\.palette, .forScheme(scheme))
    }
}
