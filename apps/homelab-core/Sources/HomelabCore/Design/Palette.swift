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
    /// Behind everything. Never used for a card.
    public let canvas: Color
    /// The default card.
    public let surface: Color
    /// A card on a card — a metric tile inside a section, a selected segment.
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
        canvas: Color(hex: 0x08090A),
        surface: Color(hex: 0x121315),
        surfaceRaised: Color(hex: 0x1A1B1E),
        border: Color(hex: 0x232428),
        borderStrong: Color(hex: 0x33353B),
        textPrimary: Color(hex: 0xEEEFF1),
        textSecondary: Color(hex: 0x8A8F98),
        textTertiary: Color(hex: 0x5E6167),
        accent: Color(hex: 0x7A82E8),
        accentMuted: Color(hex: 0x2A2C48),
        positive: Color(hex: 0x4CB782),
        warning: Color(hex: 0xE2A336),
        negative: Color(hex: 0xE5534B),
        inProgress: Color(hex: 0x4EA7FC)
    )

    public static let light = Palette(
        canvas: Color(hex: 0xF6F7F8),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xF1F2F4),
        border: Color(hex: 0xE3E5E8),
        borderStrong: Color(hex: 0xCBCFD4),
        textPrimary: Color(hex: 0x16171A),
        textSecondary: Color(hex: 0x6B7076),
        textTertiary: Color(hex: 0x9198A1),
        accent: Color(hex: 0x5E6AD2),
        accentMuted: Color(hex: 0xE7E9FA),
        positive: Color(hex: 0x2F855A),
        warning: Color(hex: 0xB7791F),
        negative: Color(hex: 0xC53030),
        inProgress: Color(hex: 0x2B6CB0)
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
}

extension Color {
    /// `0x1A1B1E` reads like the hex in a design file; three `Double`s divided
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
