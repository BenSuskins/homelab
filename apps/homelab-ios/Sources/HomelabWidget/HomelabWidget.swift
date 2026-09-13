import HomelabCore
import SwiftUI
import WidgetKit

/// The iOS answer to the menu bar glyph: something you read without opening
/// anything. Explicitly *not* an alerting mechanism — iOS treats a refresh
/// interval as a hint and may honour it hours late, so this shows what was true
/// the last time the system let it look. See ADR-0005.
@main
struct HomelabWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomelabStatusWidget()
    }
}

struct HomelabStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomelabStatus", provider: Provider()) { entry in
            HomelabWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Homelab")
        .description("The state of the three workflows.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot
    /// True when the snapshot came from the cache because a fetch was not
    /// possible — a locked device, or no network.
    let isStale: Bool
}

struct Provider: TimelineProvider {
    private static let cache = SnapshotCache(appGroup: HomelabConfiguration.iOS.appGroup ?? "")

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .placeholder, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(
            date: Date(),
            snapshot: Self.cache.load() ?? .placeholder,
            isStale: false
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // `TimelineProvider` predates `Sendable`, so its completion handler is
        // not marked as such. `Task`'s operation is a `sending` parameter, so a
        // closure that captures the handler is not Sendable and the compiler
        // rejects the whole `Task`. Boxing is what actually fixes that — the
        // capture becomes a Sendable value — where annotating the local does
        // not, because the problem is the closure, not the variable.
        //
        // Safe because WidgetKit calls the handler exactly once, from wherever
        // the work finished, which is the point of giving an async-capable API
        // a completion handler in the first place.
        let handler = UncheckedSendable(completion)

        Task {
            let entry = await Self.makeEntry()
            handler.value(Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(15 * 60))
            ))
        }
    }

    /// `static` so the `Task` above captures nothing but the boxed handler.
    private static func makeEntry() async -> Entry {
        let cached = cache.load()
        let fetched = await fetchSnapshot()

        // A failed fetch falls back to the cache rather than blanking — on a
        // locked device the Keychain is unreadable by design, and that is the
        // normal case for a widget, not an error.
        if let fetched { cache.save(fetched) }

        return Entry(
            date: Date(),
            snapshot: fetched ?? cached ?? .placeholder,
            isStale: fetched == nil
        )
    }

    private static func fetchSnapshot() async -> StatusSnapshot? {
        let tokens = KeychainTokenStore(
            service: HomelabConfiguration.iOS.keychainService,
            accessGroup: HomelabConfiguration.iOS.keychainAccessGroup
        )
        guard await tokens.token() != nil else { return nil }

        let client = GitHubClient(transport: URLSessionTransport(tokens: tokens))

        var runs: [DispatchableWorkflow: WorkflowRunSummary] = [:]
        for workflow in DispatchableWorkflow.allCases {
            guard let run = try? await client.latestRun(for: workflow) else { continue }
            runs[workflow] = run
        }
        guard !runs.isEmpty else { return nil }

        // Pull requests are not fetched: the widget never shows them, and a
        // widget refresh is a budget the system is watching.
        return StatusSnapshot.make(
            runs: runs,
            pullRequests: [],
            lastRefreshedAt: Date()
        )
    }
}

/// Carries a value the compiler cannot prove `Sendable` across an isolation
/// boundary, for the case where the API's own contract makes it safe. Used for
/// exactly one thing here — WidgetKit's pre-`Sendable` completion handler.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct HomelabWidgetView: View {
    let entry: Entry

    @Environment(\.widgetFamily) private var family

    private var glyph: GlyphState { entry.snapshot.glyph }

    /// The worst row is the one worth showing: the widget answers "do I need to
    /// open this?", exactly as the menu bar glyph does.
    private var headline: RunRow? {
        entry.snapshot.runRows.max { lhs, rhs in
            rank(lhs.status) < rank(rhs.status)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: glyph.symbolName)
                    .foregroundStyle(tint)
                Text("Homelab")
                    .font(.caption.weight(.semibold))
                Spacer()
                if entry.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let headline {
                Text(headline.workflow.displayName)
                    .font(.headline)
                Text(headline.subtitle(now: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if family == .systemMedium {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ForEach(entry.snapshot.runRows) { row in
                        HStack(spacing: 3) {
                            Image(systemName: row.presentation.symbolName)
                                .foregroundStyle(row.presentation.tint)
                            Text(row.workflow.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var tint: Color {
        switch glyph {
        case .ok: .green
        case .running: .accentColor
        case .failed: .red
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
