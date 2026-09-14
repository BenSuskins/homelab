import SwiftUI

/// The type scale. Small, tight and consistent — the app is a dashboard, and a
/// dashboard is read by scanning rather than by reading.
///
/// Every size is fixed rather than a semantic `Font.body`, because the layouts
/// here are dense grids where a two-line row becomes a three-line row and the
/// whole screen reflows. Dynamic Type is honoured through `.dynamicTypeSize`
/// clamping at the root instead, which bends the scale without breaking it.
public enum Typeface {
    /// Screen titles.
    public static let title = Font.system(size: 26, weight: .semibold)
    /// Card headlines and the big number on a tile.
    public static let headline = Font.system(size: 17, weight: .semibold)
    /// A KPI's value.
    public static func metric(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
    /// Row titles.
    public static let body = Font.system(size: 15, weight: .medium)
    /// Row subtitles, secondary detail.
    public static let caption = Font.system(size: 13, weight: .regular)
    /// Metadata: timestamps, counts, units.
    public static let footnote = Font.system(size: 11, weight: .medium)
    /// Section headers. Always uppercase, always tracked, always secondary.
    public static let sectionLabel = Font.system(size: 11, weight: .semibold)
    /// Log lines and anything else where the columns have to line up.
    public static let mono = Font.system(size: 12, design: .monospaced)
    public static let monoSmall = Font.system(size: 11, design: .monospaced)
}

/// The spacing scale, in one place so a card's padding is never a number
/// somebody picked in the moment.
public enum Metrics {
    public static let gutter: CGFloat = 16
    public static let cardPadding: CGFloat = 14
    public static let cardSpacing: CGFloat = 10
    public static let sectionSpacing: CGFloat = 22
    public static let rowSpacing: CGFloat = 12
    public static let corner: CGFloat = 12
    public static let innerCorner: CGFloat = 9
    public static let hairline: CGFloat = 1
}
