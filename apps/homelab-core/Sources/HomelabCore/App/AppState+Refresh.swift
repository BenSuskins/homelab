import Foundation

extension AppState {
    public func start() {
        guard pollingTask == nil else { return }
        invalidateHistory()
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
    /// a notification, is the ambient signal there.
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
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task {
            await performRefresh()
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        while true {
            let revision = historyRevision
            let wantsHistory = Self.isHistoryStale(historyRefreshedAt)
            do {
                let histories = try await fetchRuns(limit: wantsHistory ? Self.historyDepth : 1)
                let pullRequests = try await client.openPullRequests()
                guard revision == historyRevision else { continue }
                lastFailure = nil

                if wantsHistory {
                    history = ActivityHistory(histories: histories, lastRefreshedAt: Date())
                    historyRefreshedAt = Date()
                }

                var runs: [DispatchableWorkflow: WorkflowRunSummary] = [:]
                for entry in histories {
                    runs[entry.workflow] = entry.latest
                }

                // A successful workflow_dispatch can take several API polls to
                // appear. Keep the pending row until GitHub returns a new ID.
                // Expire it eventually if the dispatch was accepted but no run
                // ever materialised, so the UI cannot get stuck permanently.
                let now = Date()
                for (workflow, pending) in pendingDispatches {
                    let newID = runs[workflow]?.identifier
                    if (newID != nil && newID != pending.previousRunIdentifier)
                        || now.timeIntervalSince(pending.requestedAt) > 120 {
                        pendingDispatches.removeValue(forKey: workflow)
                    }
                }
                for workflow in pendingDispatches.keys {
                    runs.removeValue(forKey: workflow)
                }
                var fresh = StatusSnapshot.make(
                    runs: runs,
                    pullRequests: pullRequests,
                    lastRefreshedAt: now
                )
                fresh.runRows = fresh.runRows.map { row in
                    pendingDispatches[row.workflow] != nil
                        ? RunRow(workflow: row.workflow, status: .queued, run: nil)
                        : row
                }
                apply(fresh)
            } catch {
                guard revision == historyRevision else { continue }
                record(error)
            }
            return
        }
    }

    /// Force the next refresh to fetch the deep page, whatever the clock says —
    /// what pull-to-refresh means, and what a dispatch should do so the new run
    /// appears in its own history rather than two minutes later.
    public func invalidateHistory() {
        historyRevision += 1
        historyRefreshedAt = nil
    }

    /// How many runs back each workflow's history reaches.
    static let historyDepth = 20

    /// Runs change every ten seconds while one is active; twenty of them do not.
    static let historyInterval: TimeInterval = 120

    static func isHistoryStale(_ refreshedAt: Date?, now: Date = Date()) -> Bool {
        guard let refreshedAt else { return true }
        return now.timeIntervalSince(refreshedAt) >= historyInterval
    }

    private func fetchRuns(limit: Int) async throws(GitHubFailure) -> [RunHistory] {
        var histories: [RunHistory] = []
        for workflow in DispatchableWorkflow.allCases {
            let runs = try await client.recentRuns(for: workflow, limit: limit)
            histories.append(RunHistory(workflow: workflow, runs: runs))
        }
        return histories
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
