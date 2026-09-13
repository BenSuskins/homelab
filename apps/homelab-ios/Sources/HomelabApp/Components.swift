import HomelabCore
import SwiftUI

// The vocabulary every screen is assembled from. Nothing here knows what a
// workflow or a host is — these are surfaces, labels and tiles, and the screens
// put domain values into them.
//
// The rule they all follow: one card style, one hairline, one accent. Colour
// means status and nothing else, so a screen with nothing wrong is almost
// monochrome and the one red dot on it is impossible to miss.

// MARK: Surfaces

/// The standard card: a surface, a hairline, and the same corner radius
/// everywhere. Every block of content on every screen is one of these.
struct Card<Content: View>: View {
    @Environment(\.palette) private var palette

    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Metrics.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: Metrics.hairline)
            )
    }
}

/// A section header. Uppercase, tracked, secondary — it labels the block below
/// without competing with it, and an optional trailing slot carries a count or
/// a control.
struct SectionHeader<Trailing: View>: View {
    @Environment(\.palette) private var palette

    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Typeface.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// The page background. Applied once per screen so the canvas colour is behind
/// the scroll view, the safe areas and the navigation bar alike.
struct ScreenBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(palette.canvas.ignoresSafeArea())
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

// MARK: Indicators

/// A status dot, optionally pulsing while something is in flight. The pulse is
/// the only animation in the app: it marks the one thing that is changing while
/// you watch it.
struct StatusDot: View {
    let colour: Color
    var size: CGFloat = 8
    var isPulsing: Bool = false

    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: size, height: size)
            .overlay {
                if isPulsing {
                    Circle()
                        .stroke(colour, lineWidth: 1)
                        .scaleEffect(isExpanded ? 2.2 : 1)
                        .opacity(isExpanded ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: isExpanded
                        )
                }
            }
            .onAppear { isExpanded = isPulsing }
    }
}

/// A small capsule of text. Used for counts, states and filters — never for
/// anything tappable unless it is given an action.
struct Pill: View {
    @Environment(\.palette) private var palette

    let text: String
    var tint: Color?
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(Typeface.footnote)
        }
        .foregroundStyle(tint ?? palette.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((tint ?? palette.textSecondary).opacity(0.12))
        )
    }
}

/// An arrow and a percentage, for a number that has moved. Silent below a
/// threshold, because a dashboard that flags every 2% wobble trains you to
/// ignore it.
struct TrendBadge: View {
    @Environment(\.palette) private var palette

    let change: Double?
    /// Whether going up is bad. True for durations and utilisation, false for
    /// anything where more is better.
    var risingIsBad: Bool = true
    var threshold: Double = 0.1

    var body: some View {
        if let change, abs(change) >= threshold {
            let rising = change > 0
            let bad = rising == risingIsBad
            HStack(spacing: 2) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(Int((abs(change) * 100).rounded()))%")
                    .font(Typeface.footnote)
            }
            .foregroundStyle(bad ? palette.warning : palette.textTertiary)
        }
    }
}

// MARK: Tiles

/// One number and its label. Four of these across is the status strip every
/// screen opens with, which is the `Status` row from the dashboard style guide.
struct StatTile: View {
    @Environment(\.palette) private var palette

    let label: String
    let value: String
    var tint: Color?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Typeface.metric(20))
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Typeface.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                .fill(palette.surfaceRaised)
        )
    }
}

/// The strip of tiles itself, so no screen has to remember the spacing.
struct StatStrip<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
    }
}

// MARK: Controls

/// The segmented control the charts are scoped by. Rolled by hand rather than
/// `Picker(.segmented)`, which cannot be tinted to the palette and brings its
/// own idea of a background.
struct SegmentedControl<Value: Hashable & Identifiable>: View {
    @Environment(\.palette) private var palette

    let values: [Value]
    let title: (Value) -> String
    let selection: Value
    /// A closure rather than a `Binding`, because selecting a window starts a
    /// fetch on a `@MainActor` monitor and a binding's setter is not isolated.
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values) { value in
                let isSelected = value == selection
                Button {
                    onSelect(value)
                } label: {
                    Text(title(value))
                        .font(Typeface.footnote)
                        .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? palette.surface : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceRaised)
        )
    }
}

/// The small square button that starts or stops a workflow.
struct IconButton: View {
    @Environment(\.palette) private var palette

    let symbol: String
    var tint: Color?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? (tint ?? palette.textPrimary) : palette.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: Metrics.hairline)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// The empty and unreachable states. `ContentUnavailableView` would do the job
/// but brings system colours with it, and these show up often enough — every
/// screen off the tailnet — to be worth drawing in the palette.
struct EmptyState: View {
    @Environment(\.palette) private var palette

    let title: String
    let message: String
    var symbol: String = "tray"
    var tint: Color?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint ?? palette.textTertiary)
            Text(title)
                .font(Typeface.body)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

/// The line every tailnet-only screen shows when it is off the tailnet. One
/// component so the wording cannot drift between Health and Logs.
struct OffTailnetNotice: View {
    @Environment(\.palette) private var palette

    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.system(size: 11, weight: .medium))
            Text(detail)
                .font(Typeface.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                .fill(palette.surfaceRaised)
        )
    }
}

/// A labelled row of small text, used inside cards for host readings and run
/// metadata.
struct Reading: View {
    @Environment(\.palette) private var palette

    let label: String
    let value: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            // A metric that is not reporting says so, rather than showing a
            // zero that reads like a healthy measurement.
            Text(value ?? "—")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(value == nil ? palette.textTertiary : (tint ?? palette.textPrimary))
        }
    }
}
