import HomelabCore
import SwiftUI
import WidgetKit

/// The workflows, at four sizes plus the lock screen. The question it answers
/// is the menu bar glyph's: do I need to open this?
struct HomelabStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomelabStatus", provider: StatusProvider()) { entry in
            WidgetSurface { StatusWidgetView(entry: entry) }
        }
        .configurationDisplayName("Workflows")
        .description("Update, Terraform and Clean — what each one last did.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot
    /// True when the snapshot came from the cache because a fetch was not
    /// possible — a locked device, or no network.
    let isStale: Bool
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .placeholder, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(
            date: Date(),
            snapshot: WidgetData.snapshotCache.load() ?? .placeholder,
            isStale: false
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let handler = UncheckedSendable(completion)

        Task {
            let entry = await Self.makeEntry()
            handler.value(Timeline(
                entries: [entry],
                policy: .after(WidgetData.nextRefresh(active: entry.snapshot.hasActiveRun))
            ))
        }
    }

    /// `static` so the `Task` above captures nothing but the boxed handler.
    private static func makeEntry() async -> StatusEntry {
        let cached = WidgetData.snapshotCache.load()
        let fetched = await WidgetData.fetchStatus()

        // A failed fetch falls back to the cache rather than blanking — on a
        // locked device the Keychain is unreadable by design, and that is the
        // normal case for a widget, not an error.
        if let fetched { WidgetData.snapshotCache.save(fetched) }

        return StatusEntry(
            date: Date(),
            snapshot: fetched ?? cached ?? .placeholder,
            isStale: fetched == nil
        )
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.palette) private var palette

    private var glyph: GlyphState { entry.snapshot.glyph }

    /// The worst row is the one worth showing: the widget answers "do I need to
    /// open this?", exactly as the menu bar glyph does.
    private var headline: RunRow? {
        entry.snapshot.runRows.max { rank($0.status) < rank($1.status) }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        default:
            wide
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Homelab", tint: palette.color(for: glyph), isStale: entry.isStale)

            if let headline {
                Text(headline.workflow.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(headline.subtitle(now: entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            } else {
                Text("No data yet")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(entry.snapshot.runRows) { row in
                    Capsule()
                        .fill(palette.color(for: row.status))
                        .frame(height: 3)
                }
            }
        }
    }

    private var wide: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                title: headlineText,
                tint: palette.color(for: glyph),
                isStale: entry.isStale
            )

            VStack(spacing: family == .systemLarge ? 10 : 6) {
                ForEach(entry.snapshot.runRows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(palette.color(for: row.status))
                            .frame(width: 7, height: 7)
                        Text(row.workflow.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 4)
                        Text(row.subtitle(now: entry.date))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            if family == .systemLarge {
                Spacer(minLength: 0)

                if entry.snapshot.pullRequests.isEmpty {
                    Text("No open pull requests")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                } else {
                    Text("\(entry.snapshot.pullRequests.count) open pull requests")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if let refreshed = entry.snapshot.lastRefreshedAt {
                Text("Updated \(RelativeTime.ago(refreshed, now: entry.date))")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Lock screen

    /// Accessory families render tinted or monochrome, so these carry no colour
    /// of their own — the symbol does the work.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: glyph.symbolName)
                    .font(.system(size: 14, weight: .medium))
                Text(shortStatus)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: glyph.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text("Homelab")
                    .font(.system(size: 12, weight: .semibold))
            }
            if let headline {
                Text(headline.workflow.displayName)
                    .font(.system(size: 12))
                Text(headline.subtitle(now: entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inlineText: String {
        guard let headline else { return "Homelab · no data" }
        return "\(headline.workflow.displayName) · \(RunStatusPresentation(headline.status).label)"
    }

    // MARK: Wording

    private var headlineText: String {
        switch glyph {
        case .ok: "All green"
        case .running: "Running"
        case .failed: "Needs attention"
        }
    }

    private var shortStatus: String {
        switch glyph {
        case .ok: "OK"
        case .running: "RUN"
        case .failed: "FAIL"
        }
    }

    private func rank(_ status: RunStatus) -> Int {
        switch status {
        case .failed: 3
        case .running, .queued: 2
        case .awaitingApproval: 1
        case .succeeded, .cancelled, .never: 0
        }
    }
}
