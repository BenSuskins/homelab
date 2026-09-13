import HomelabCore
import SwiftUI

struct RunsView: View {
    @Environment(AppState.self) private var state
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                ForEach(state.snapshot.runRows) { row in
                    RunRowView(row: row)
                }
            } footer: {
                if let error = state.snapshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Links") {
                ForEach(state.quickLinks) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Label(link.title, systemImage: link.symbolName)
                    }
                }
            }

            Section {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
        .navigationTitle("Homelab")
        .refreshable { await state.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let refreshed = state.snapshot.lastRefreshedAt {
                    Text(RelativeTime.ago(refreshed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RunRowView: View {
    let row: RunRow

    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.presentation.symbolName)
                .foregroundStyle(row.presentation.tint)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.workflow.displayName)
                    .font(.body.weight(.medium))
                Text(row.subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            control
        }
        .contentShape(.rect)
        .onTapGesture {
            openURL(row.run?.url ?? state.repository.actionsURL)
        }
    }

    @ViewBuilder
    private var control: some View {
        if state.busyWorkflows.contains(row.workflow) {
            ProgressView()
        } else if state.canCancel(row.workflow) {
            Button {
                Task { await state.cancel(row.workflow) }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        } else {
            Button {
                Task { await state.trigger(row.workflow) }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!state.canTrigger(row.workflow))
        }
    }
}
