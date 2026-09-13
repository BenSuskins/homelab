import Foundation

extension AppState {
    public func start() {
        Task { await notifier.requestAuthorization() }
        reconcileLaunchAtLogin()
        restartPolling()
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// One loop that re-reads its own interval after every pass, so a dispatch
    /// that starts a run tightens the cadence without a second timer.
    ///
    /// On iOS this runs only while the app is foregrounded — the scene phase
    /// drives `start()` and `stop()`, because a suspended app's loop is stopped
    /// by the system regardless of what we intend. That is why the widget, not
    /// a notification, is the ambient signal there (ADR-0005).
    public func restartPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = PollingSchedule.interval(for: self.snapshot)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let runs = try await fetchLatestRuns()
            let pullRequests = try await client.openPullRequests()
            lastFailure = nil
            apply(
                StatusSnapshot.make(
                    runs: runs,
                    pullRequests: pullRequests,
                    lastRefreshedAt: Date()
                )
            )
        } catch {
            // Keep the last good data on screen; a failed poll is not a reason
            // to blank the display.
            record(error)
        }
    }

    private func fetchLatestRuns() async throws(GitHubFailure) -> [DispatchableWorkflow: WorkflowRunSummary] {
        var runs: [DispatchableWorkflow: WorkflowRunSummary] = [:]
        for workflow in DispatchableWorkflow.allCases {
            if let run = try await client.latestRun(for: workflow) {
                runs[workflow] = run
            }
        }
        return runs
    }

    private func apply(_ fresh: StatusSnapshot) {
        let failures = FailureDetector.newFailures(previous: snapshot, current: fresh)
        snapshot = fresh
        cache.save(fresh)

        for failure in failures {
            Task { [notifier] in await notifier.notify(failure) }
        }
    }
}
