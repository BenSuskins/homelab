import Foundation
import Observation

@MainActor
@Observable
public final class AppState {
    public internal(set) var snapshot: StatusSnapshot
    /// The past, beside the present: the last several runs of each workflow.
    /// Kept off `StatusSnapshot` deliberately — that value is cached for the
    /// widget and shared with macOS, and a widget has no use for twenty runs it
    /// will never draw.
    public internal(set) var history = ActivityHistory()
    public internal(set) var isRefreshing = false
    /// The last failure as a value, not as its rendered message. The snapshot
    /// carries `errorMessage` for display; this is what code branches on, so
    /// that "the grant was revoked" is a case match rather than a string
    /// comparison against text someone might reword.
    public internal(set) var lastFailure: GitHubFailure?
    /// Workflows and pull requests with an in-flight write, so their button can
    /// show a spinner and refuse a second click before the next poll lands.
    public internal(set) var busyWorkflows: Set<DispatchableWorkflow> = []
    public internal(set) var busyPullRequests: Set<Int> = []
    public internal(set) var loginItemStatus: LoginItemStatus = .disabled
    public internal(set) var launchAtLoginError: String?

    public let repository: RepositoryReference

    public let client: GitHubClient
    public let cache: SnapshotCache
    public let notifier: any FailureNotifying
    public let loginItem: any LoginItemControlling
    public let launchAtLoginPreference: LaunchAtLoginPreference
    public let writeAuthorisation: any WriteAuthorising
    var pollingTask: Task<Void, Never>?
    /// When the deep page of runs was last fetched. A poll during an active run
    /// comes round every ten seconds and history does not change that fast, so
    /// most passes ask for one run rather than twenty.
    var historyRefreshedAt: Date?

    public init(
        client: GitHubClient,
        repository: RepositoryReference = .homelab,
        cache: SnapshotCache = SnapshotCache(),
        notifier: any FailureNotifying = SilentFailureNotifier(),
        loginItem: any LoginItemControlling = UnsupportedLoginItemService(),
        launchAtLoginPreference: LaunchAtLoginPreference = LaunchAtLoginPreference(),
        writeAuthorisation: any WriteAuthorising = AlwaysAuthorised()
    ) {
        self.client = client
        self.repository = repository
        self.cache = cache
        self.notifier = notifier
        self.loginItem = loginItem
        self.launchAtLoginPreference = launchAtLoginPreference
        self.writeAuthorisation = writeAuthorisation
        self.snapshot = cache.load() ?? .placeholder
    }

    public var quickLinks: [QuickLink] {
        QuickLink.standard(for: repository)
    }

    public func canTrigger(_ workflow: DispatchableWorkflow) -> Bool {
        guard !busyWorkflows.contains(workflow) else { return false }
        return snapshot.row(for: workflow)?.canTrigger ?? false
    }

    public func canCancel(_ workflow: DispatchableWorkflow) -> Bool {
        guard !busyWorkflows.contains(workflow) else { return false }
        return snapshot.row(for: workflow)?.canCancel ?? false
    }

    public func isBusy(pullRequest number: Int) -> Bool {
        busyPullRequests.contains(number)
    }

    /// Pull requests worth acting on, newest first: the ones GitHub says will
    /// merge cleanly. Drafts and conflicts stay in the list, just not here.
    public var mergeablePullRequests: [PullRequestSummary] {
        snapshot.pullRequests.filter(\.canMerge)
    }

    /// Named `runHistory` rather than overloading `history`, which is the
    /// property right above it — a method and a property sharing a base name is
    /// legal and reads like a mistake.
    public func runHistory(for workflow: DispatchableWorkflow) -> RunHistory? {
        history.history(for: workflow)
    }

    /// Exposed so a view can replace a stale snapshot (a widget handing one
    /// over, a test seeding history) without going through a refresh.
    public func adopt(_ snapshot: StatusSnapshot) {
        self.snapshot = snapshot
    }

    func markBusy(workflow: DispatchableWorkflow, _ busy: Bool) {
        if busy {
            busyWorkflows.insert(workflow)
        } else {
            busyWorkflows.remove(workflow)
        }
    }

    func markBusy(pullRequest number: Int, _ busy: Bool) {
        if busy {
            busyPullRequests.insert(number)
        } else {
            busyPullRequests.remove(number)
        }
    }

    func record(_ failure: GitHubFailure?) {
        lastFailure = failure
        var updated = snapshot
        updated.errorMessage = failure?.displayMessage
        snapshot = updated
    }
}
