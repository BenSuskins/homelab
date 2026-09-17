import HomelabCore
import SwiftUI
import UIKit

/// One log line, opened.
///
/// The list has to truncate — three lines of message, three chips — so this is
/// where the rest of it lives: every field the line declared, every label Loki
/// stamped it with, both timestamps, and the raw line underneath them in case
/// the parse got something wrong. Nothing here is fetched; it is all already in
/// the entry, which is why it opens instantly and works off the tailnet.
struct LogDetailView: View {
    let entry: LokiLogEntry
    /// Narrows the list behind the sheet to this line's container. The most
    /// common thing to want next is "show me everything else this one said".
    let onIsolateContainer: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var isShowingRaw = false
    @State private var copied: String?

    private var record: LogRecord { entry.record }
    private var tint: Color { palette.color(for: record.level) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                    heading
                    message
                    if !record.fields.isEmpty { fields }
                    labels
                    raw
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Log line")
            .navigationBarTitleDisplayMode(.inline)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(Typeface.caption)
                        .foregroundStyle(palette.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Copy message") { copy(record.message, as: "message") }
                        Button("Copy raw line") { copy(entry.line, as: "raw line") }
                        if let container = entry.container {
                            Divider()
                            Button("Only \(container)") { onIsolateContainer(container) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let copied {
                    Text("Copied the \(copied)")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(palette.surfaceRaised))
                        .overlay(Capsule().strokeBorder(palette.border, lineWidth: Metrics.hairline))
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Status

    private var heading: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Pill(text: record.level.label, tint: tint)

                    // Says whether the level is the line's own word or ours.
                    // A guess is fine for tinting a row and is not fine as a
                    // fact on a detail screen, so the screen admits which it is.
                    Text(record.declaresLevel ? "declared" : "inferred")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)

                    Spacer(minLength: 0)

                    Pill(text: record.shape.label)
                }

                if let container = entry.container {
                    Button {
                        onIsolateContainer(container)
                    } label: {
                        HStack(spacing: 5) {
                            Text(container)
                                .font(Typeface.headline)
                                .foregroundStyle(palette.textPrimary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.accent)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 14) {
                    Reading(label: "Host", value: entry.host)
                    Reading(label: "Written", value: LogTime.clock(entry.writtenAt))
                    // Only worth the space when the two disagree: when they do,
                    // the gap between them is the ingest lag.
                    if record.timestamp != nil {
                        Reading(
                            label: "Ingested",
                            value: LogTime.clock(entry.timestamp),
                            tint: palette.textSecondary
                        )
                    }
                }

                Text(LogTime.stamp(entry.writtenAt))
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Body

    private var message: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Message")
                Text(record.message)
                    .font(Typeface.mono)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var fields: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Fields") {
                    Text("\(record.fields.count)")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
                KeyValueTable(pairs: record.fields)
            }
        }
    }

    private var labels: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Stream labels")
                KeyValueTable(
                    pairs: entry.labels
                        .sorted { $0.key < $1.key }
                        .map { LogField(key: $0.key, value: $0.value) }
                )
            }
        }
    }

    /// Collapsed, because the whole point of the screen above it is that you
    /// should not have to read this. Open when the parse looks wrong.
    private var raw: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isShowingRaw.toggle() }
                } label: {
                    HStack {
                        SectionHeader("Raw line")
                        Image(systemName: isShowingRaw ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                if isShowingRaw {
                    Text(entry.line)
                        .font(Typeface.monoSmall)
                        .foregroundStyle(palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func copy(_ value: String, as name: String) {
        UIPasteboard.general.string = value
        withAnimation { copied = name }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copied = nil }
        }
    }
}

/// Keys down the left, values down the right, values selectable and wrapping.
/// A `Grid` rather than an `HStack` per row so the keys line up, which is the
/// only reason a table beats a list of chips here.
private struct KeyValueTable: View {
    let pairs: [LogField]

    @Environment(\.palette) private var palette

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(pairs) { pair in
                GridRow {
                    Text(pair.key)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .gridColumnAlignment(.leading)

                    Text(pair.value.isEmpty ? "—" : pair.value)
                        .font(Typeface.monoSmall)
                        .foregroundStyle(
                            pair.value.isEmpty ? palette.textTertiary : palette.textPrimary
                        )
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
