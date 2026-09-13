import HomelabCore
import SwiftUI
import WidgetKit

/// What is waiting for a decision. Renovate opens most of these, so the useful
/// distinction is not "how many" but "how many will merge cleanly" — that is
/// the number this widget leads with.
struct HomelabPullRequestsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomelabPullRequests", provider: PullRequestProvider()) { entry in
            WidgetSurface { PullRequestWidgetView(entry: entry) }
        }
        .configurationDisplayName("Pull requests")
        .description("Open pull requests, and how many are ready to merge.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct PullRequestEntry: TimelineEntry {
    let date: Date
    let pullRequests: [PullRequestSummary]
    let isStale: Bool

    var mergeable: [PullRequestSummary] { pullRequests.filter(\.canMerge) }
}

struct PullRequestProvider: TimelineProvider {
    func placeholder(in context: Context) -> PullRequestEntry {
        PullRequestEntry(date: Date(), pullRequests: [], isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PullRequestEntry) -> Void) {
        completion(PullRequestEntry(
            date: Date(),
            pullRequests: WidgetData.snapshotCache.load()?.pullRequests ?? [],
            isStale: false
        ))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PullRequestEntry>) -> Void
    ) {
        let handler = UncheckedSendable(completion)

        Task {
            let entry = await Self.makeEntry()
            handler.value(Timeline(
                entries: [entry],
                policy: .after(WidgetData.nextRefresh(active: false))
            ))
        }
    }

    private static func makeEntry() async -> PullRequestEntry {
        let cached = WidgetData.snapshotCache.load()
        let fetched = await WidgetData.fetchStatus()

        if let fetched { WidgetData.snapshotCache.save(fetched) }

        return PullRequestEntry(
            date: Date(),
            pullRequests: fetched?.pullRequests ?? cached?.pullRequests ?? [],
            isStale: fetched == nil
        )
    }
}

struct PullRequestWidgetView: View {
    let entry: PullRequestEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.palette) private var palette

    private var tint: Color {
        entry.mergeable.isEmpty ? palette.textSecondary : palette.accent
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Pull requests", tint: tint, isStale: entry.isStale)

            Text("\(entry.pullRequests.count)")
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)

            Text(entry.pullRequests.isEmpty ? "none open" : "\(entry.mergeable.count) ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.mergeable.isEmpty ? palette.textSecondary : palette.accent)

            Spacer(minLength: 0)

            if let first = entry.mergeable.first ?? entry.pullRequests.first {
                Text(first.title)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(
                title: entry.pullRequests.isEmpty
                    ? "No open pull requests"
                    : "\(entry.pullRequests.count) open · \(entry.mergeable.count) ready",
                tint: tint,
                isStale: entry.isStale
            )

            if entry.pullRequests.isEmpty {
                Spacer(minLength: 0)
                Text("Renovate will be along shortly.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sorted.prefix(3)) { pullRequest in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(pullRequest.canMerge ? palette.positive : palette.textTertiary)
                                .frame(width: 5, height: 5)
                            Text("#\(pullRequest.number)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(palette.textSecondary)
                            Text(pullRequest.title)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Ready first: the list exists to be acted on, and a draft is not
    /// something anyone is going to do anything about from a home screen.
    private var sorted: [PullRequestSummary] {
        entry.pullRequests.sorted { lhs, rhs in
            if lhs.canMerge != rhs.canMerge { return lhs.canMerge }
            return lhs.number > rhs.number
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.trianglehead.pull")
                    .font(.system(size: 11, weight: .medium))
                Text("Pull requests")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(inlineText)
                .font(.system(size: 12))
            if let first = sorted.first {
                Text(first.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inlineText: String {
        entry.pullRequests.isEmpty
            ? "No open pull requests"
            : "\(entry.pullRequests.count) open · \(entry.mergeable.count) ready"
    }
}
