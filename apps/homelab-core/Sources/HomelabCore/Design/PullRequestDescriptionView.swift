import SwiftUI

/// Both apps read the same description without placing it in the cached list.
public struct PullRequestDescriptionView: View {
    public let pullRequest: PullRequestSummary
    @Environment(AppState.self) private var state
    @State private var description: PullRequestDescription?
    @State private var failure: GitHubFailure?
    @State private var isLoading = false

    public init(pullRequest: PullRequestSummary) {
        self.pullRequest = pullRequest
    }

    private var current: PullRequestSummary? {
        state.snapshot.pullRequests.first { $0.number == pullRequest.number }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(pullRequest.title).font(.title2.weight(.semibold))
                Text("#\(pullRequest.number) · \(pullRequest.authorLogin) · \(RelativeTime.ago(pullRequest.createdAt))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let description {
                    Text("Target: \(description.baseBranch)").font(.subheadline).foregroundStyle(.secondary)
                }
                if let current {
                    Text(current.isDraft ? "Draft" : readiness(current.readiness))
                        .font(.subheadline.weight(.medium))
                    if current.canMerge {
                        Text("Squash merge starts Update Homelab on \(state.repository.defaultBranch).")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Squash merge #\(current.number)") {
                            Task { await state.merge(current) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isBusy(pullRequest: current.number))
                    }
                } else {
                    Text("This pull request is no longer in the open list.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if state.isBusy(pullRequest: pullRequest.number) { ProgressView("Submitting merge…") }
                if let failure = state.actionFailure {
                    HStack(alignment: .top, spacing: 12) {
                        Label(failure.displayMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("Dismiss") { state.clearActionFailure() }
                    }
                }
                Link("Open on GitHub", destination: pullRequest.url)
                Divider()
                if isLoading { ProgressView("Loading description…") }
                if let failure {
                    Label(failure.displayMessage, systemImage: "exclamationmark.triangle")
                    Button("Retry") { Task { await load() } }
                }
                if let description {
                    if description.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No description provided").foregroundStyle(.secondary)
                    } else {
                        DescriptionMarkdown(source: description.body, baseURL: pullRequest.url)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Pull request #\(pullRequest.number)")
        .task { await load() }
    }

    private func readiness(_ value: MergeReadiness) -> String {
        switch value {
        case .mergeable: "Ready to merge"
        case .conflicting: "Conflicts prevent merge"
        case .unknown: "GitHub is checking merge readiness"
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            description = try await state.client.pullRequestDescription(number: pullRequest.number)
        } catch {
            failure = error
        }
    }
}

private struct DescriptionMarkdown: View {
    let source: String
    let baseURL: URL

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(inline(text)).frame(maxWidth: .infinity, alignment: .leading)
                case .heading(let text, let level):
                    Text(inline(text)).font(level == 1 ? .title2.bold() : .headline)
                        .accessibilityAddTraits(.isHeader)
                case .code(let text):
                    ScrollView(.horizontal) {
                        Text(text).font(.callout.monospaced()).padding(12)
                    }
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                case .quote(let text):
                    HStack(alignment: .top) {
                        Rectangle().fill(.secondary).frame(width: 3)
                        Text(inline(text)).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .table(let rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 10) {
                            ForEach(rows.indices, id: \.self) { row in
                                GridRow {
                                    ForEach(rows[row].indices, id: \.self) { column in
                                        Text(inline(rows[row][column]))
                                            .fontWeight(row == 0 ? .semibold : .regular)
                                            .frame(maxWidth: 300, alignment: .leading)
                                    }
                                }
                                Divider()
                            }
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }

    var body: some View { bodyView }

    private enum Block {
        case text(String), heading(String, Int), code(String), quote(String), table([[String]])
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ), baseURL: baseURL)) ?? AttributedString(text)
    }

    private var blocks: [Block] {
        let lines = source.components(separatedBy: .newlines)
        var result: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                result.append(.code(code.joined(separator: "\n")))
            } else if trimmed.hasPrefix("#"), let space = trimmed.firstIndex(of: " "),
                      trimmed[..<space].allSatisfy({ $0 == "#" }) {
                result.append(.heading(String(trimmed[trimmed.index(after: space)...]), trimmed.distance(from: trimmed.startIndex, to: space)))
            } else if trimmed.hasPrefix("> ") {
                result.append(.quote(String(trimmed.dropFirst(2))))
            } else if index + 1 < lines.count, line.contains("|"), isTableSeparator(lines[index + 1]) {
                var rows = [cells(line)]
                index += 2
                while index < lines.count && lines[index].contains("|") && !lines[index].isEmpty {
                    rows.append(cells(lines[index])); index += 1
                }
                result.append(.table(rows))
                continue
            } else if !trimmed.isEmpty {
                let text = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
                    ? "• " + String(trimmed.dropFirst(2)) : line
                result.append(.text(String(text)))
            }
            index += 1
        }
        return result
    }

    private func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy {
            let value = $0.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }
}
