import SwiftUI

/// Semantic styles preserve the system text size on every surface.
public enum Typeface {
    public static let title = Font.title2.weight(.semibold)
    public static let headline = Font.headline
    public static func metric(_ size: CGFloat = 24) -> Font {
        (size >= 24 ? Font.title2 : Font.title3).weight(.semibold).monospacedDigit()
    }
    public static let body = Font.body
    public static let caption = Font.subheadline
    public static let footnote = Font.footnote
    public static let sectionLabel = Font.subheadline.weight(.semibold)
    public static let mono = Font.callout.monospaced()
    public static let monoSmall = Font.footnote.monospaced()
}

public enum Metrics {
    public static let gutter: CGFloat = 16
    public static let cardPadding: CGFloat = 0
    public static let cardSpacing: CGFloat = 12
    public static let sectionSpacing: CGFloat = 24
    public static let rowSpacing: CGFloat = 12
    public static let corner: CGFloat = 12
    public static let innerCorner: CGFloat = 9
    public static let hairline: CGFloat = 1
}
