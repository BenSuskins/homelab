import HomelabCore
import SwiftUI

// Shared layout and controls for the flat dashboard.

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
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }
}

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
            Text(title)
                .font(Typeface.sectionLabel)
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

struct ScreenBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(palette.canvas.ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

// MARK: Indicators

struct StatusDot: View {
    let colour: Color
    var size: CGFloat = 8
    var isPulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: size, height: size)
            .overlay {
                if isPulsing && !reduceMotion {
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
            .onAppear { isExpanded = isPulsing && !reduceMotion }
            .accessibilityHidden(true)
    }
}

struct Pill: View {
    @Environment(\.palette) private var palette

    let text: String
    var tint: Color?
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(Typeface.footnote.weight(.bold))
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

struct TrendBadge: View {
    @Environment(\.palette) private var palette

    let change: Double?
    var risingIsBad: Bool = true
    var threshold: Double = 0.1

    var body: some View {
        if let change, abs(change) >= threshold {
            let rising = change > 0
            let bad = rising == risingIsBad
            HStack(spacing: 2) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(Typeface.footnote.weight(.bold))
                Text("\(Int((abs(change) * 100).rounded()))%")
                    .font(Typeface.footnote)
            }
            .foregroundStyle(bad ? palette.warning : palette.textTertiary)
        }
    }
}

// MARK: Tiles

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
            Text(label)
                .font(Typeface.sectionLabel)
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
    }
}

struct StatStrip<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 12))
        layout { content }
            .padding(.vertical, 12)
    }
}

// MARK: Controls

struct SegmentedControl<Value: Hashable & Identifiable>: View {
    @Environment(\.palette) private var palette

    let values: [Value]
    let title: (Value) -> String
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        Picker("Time range", selection: Binding(get: { selection }, set: onSelect)) {
            ForEach(values) { value in
                Text(title(value)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
    }
}

struct IconButton: View {
    @Environment(\.palette) private var palette

    let symbol: String
    var label: String
    var tint: Color?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? (tint ?? palette.textPrimary) : palette.textTertiary)
                .frame(width: 44, height: 44)
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
        .accessibilityLabel(label)
    }
}

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

struct OffTailnetNotice: View {
    @Environment(\.palette) private var palette

    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(Typeface.footnote)
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

struct Reading: View {
    @Environment(\.palette) private var palette

    let label: String
    let value: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Typeface.footnote)
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            // A metric that is not reporting says so, rather than showing a
            // zero that reads like a healthy measurement.
            Text(value ?? "No data")
                .font(Typeface.caption.monospacedDigit())
                .foregroundStyle(value == nil ? palette.textTertiary : (tint ?? palette.textPrimary))
        }
    }
}

struct RequestFailure: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Typeface.caption)
                .foregroundStyle(.red)
            Button("Retry") { Task { await retry() } }
                .frame(minHeight: 44)
        }
    }
}
