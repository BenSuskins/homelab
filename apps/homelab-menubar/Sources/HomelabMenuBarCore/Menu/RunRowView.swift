import HomelabCore
import SwiftUI

struct RunRowView: View {
    let row: RunRow

    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.presentation.symbolName)
                .foregroundStyle(row.presentation.tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.workflow.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(row.subtitle())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.busyWorkflows.contains(row.workflow) {
                ProgressView().controlSize(.small)
            } else if state.canCancel(row.workflow) {
                Button {
                    Task { await state.cancel(row.workflow) }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel this run")
            } else {
                Button {
                    Task { await state.trigger(row.workflow) }
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!state.canTrigger(row.workflow))
                .help(row.workflow.summary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture {
            openURL(row.run?.url ?? state.repository.actionsURL)
        }
    }
}
