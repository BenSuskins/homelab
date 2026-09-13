import HomelabCore
import SwiftUI
import WidgetKit

/// The iOS answer to the menu bar glyph: things you read without opening
/// anything. Explicitly *not* an alerting mechanism — iOS treats a refresh
/// interval as a hint and may honour it hours late, so these show what was true
/// the last time the system let them look. See ADR-0005.
///
/// There are three of them because one was not enough: runs answer "did my
/// deploy work", health answers "is anything down", and pull requests answer
/// "is there something waiting for me". Each offers the home-screen families
/// and, where the content fits in a sentence, the lock-screen ones too.
@main
struct HomelabWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomelabStatusWidget()
        HomelabHealthWidget()
        HomelabPullRequestsWidget()
    }
}

// MARK: Shared plumbing

enum WidgetData {
    static var snapshotCache: SnapshotCache {
        SnapshotCache(appGroup: HomelabConfiguration.iOS.appGroup ?? "")
    }

    static var healthCache: HealthCache {
        HealthCache(appGroup: HomelabConfiguration.iOS.appGroup ?? "")
    }

    /// How long until the system is next asked to refresh. A request, not a
    /// promise — see ADR-0005.
    static func nextRefresh(active: Bool) -> Date {
        // A run in flight changes minute to minute; an idle homelab does not.
        Date().addingTimeInterval(active ? 5 * 60 : 15 * 60)
    }

    static func client() async -> GitHubClient? {
        let tokens = KeychainTokenStore(
            service: HomelabConfiguration.iOS.keychainService,
            accessGroup: HomelabConfiguration.iOS.keychainAccessGroup
        )
        // On a locked device the Keychain item is unreadable by design. That is
        // the normal case for a widget, not an error: the caller falls back to
        // the App Group cache.
        guard await tokens.token() != nil else { return nil }
        return GitHubClient(transport: URLSessionTransport(tokens: tokens))
    }

    /// The latest run of each workflow and the open pull requests — never a
    /// run's history, which no widget draws and which a refresh budget the
    /// system is watching would not thank us for.
    ///
    /// Both halves every time, even for a widget that shows one of them: all
    /// three widgets share the App Group snapshot, so a fetch that wrote back
    /// only the runs would delete the pull requests out from under the one that
    /// draws them.
    static func fetchStatus() async -> StatusSnapshot? {
        guard let client = await client() else { return nil }

        var runs: [DispatchableWorkflow: WorkflowRunSummary] = [:]
        for workflow in DispatchableWorkflow.allCases {
            guard let run = try? await client.latestRun(for: workflow) else { continue }
            runs[workflow] = run
        }

        let pullRequests = (try? await client.openPullRequests()) ?? []

        guard !runs.isEmpty || !pullRequests.isEmpty else { return nil }

        return StatusSnapshot.make(
            runs: runs,
            pullRequests: pullRequests,
            lastRefreshedAt: Date()
        )
    }

    /// Health comes from Prometheus, which is tailnet-only, so this usually
    /// fails and the cache is what gets drawn. Worth attempting anyway: a phone
    /// at home is on the tailnet, which is exactly when the number matters.
    static func fetchHealth() async -> HealthSnapshot? {
        let client = PrometheusClient()
        guard let samples = try? await client.instantQuery(HealthQuery.serviceSuccess),
              !samples.isEmpty else { return nil }

        let services = samples.compactMap { sample -> ServiceHealth? in
            guard let name = sample["name"] else { return nil }
            return ServiceHealth(
                name: name,
                host: sample["group"] ?? "Unknown",
                isUp: sample.value == 1
            )
        }
        .sorted { ($0.host, $0.name) < ($1.host, $1.name) }

        return HealthSnapshot(services: services, hosts: [], lastRefreshedAt: Date())
    }
}

/// Carries a value the compiler cannot prove `Sendable` across an isolation
/// boundary, for the case where the API's own contract makes it safe.
///
/// `TimelineProvider` predates `Sendable`, so its completion handler is not
/// marked as such. `Task`'s operation is a `sending` parameter, so a closure
/// capturing the handler is not Sendable and the compiler rejects the whole
/// `Task`. Boxing is what actually fixes that — the capture becomes a Sendable
/// value — where annotating the local does not, because the problem is the
/// closure, not the variable. Safe because WidgetKit calls the handler exactly
/// once, from wherever the work finished.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: Shared views

/// Wraps a widget's content in the palette and the container background, so
/// every widget picks up the same appearance with one line.
struct WidgetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .homelabPalette(colorScheme)
            .containerBackground(for: .widget) {
                Palette.forScheme(colorScheme).canvas
            }
    }
}

/// The line every widget carries at the top: a dot, a name, and a clock when
/// what is on screen came out of the cache rather than off the network.
struct WidgetHeader: View {
    @Environment(\.palette) private var palette

    let title: String
    let tint: Color
    let isStale: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            if isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}
