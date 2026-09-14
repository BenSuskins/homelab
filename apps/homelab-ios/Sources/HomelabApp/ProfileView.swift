import HomelabCore
import SwiftUI

/// Everything that is about the app rather than about the homelab: which
/// account it is signed in as, what it is pointed at, and the way out.
///
/// Sign-out lives here because it used to sit two rows under the button that
/// deploys six hosts. A sheet behind an avatar is one deliberate tap further
/// away, which for the only irreversible control in the app is the right
/// distance.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isConfirmingSignOut = false

    private var state: AppState? { session.appState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    account
                    repository
                    about
                    signOut
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Typeface.caption)
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }

    // MARK: Sections

    private var account: some View {
        Card {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.viewer?.displayName ?? "Signed in")
                        .font(Typeface.headline)
                        .foregroundStyle(palette.textPrimary)
                    Text(session.viewer.map { "@\($0.login)" } ?? "GitHub device flow")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: 0)

                if let url = session.viewer?.profileURL {
                    IconButton(symbol: "arrow.up.right", tint: palette.textSecondary) {
                        openURL(url)
                    }
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(palette.surfaceRaised)
                .overlay(Circle().strokeBorder(palette.border, lineWidth: Metrics.hairline))

            if let url = session.viewer?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(session.viewer?.initial ?? "?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(width: 46, height: 46)
    }

    private var repository: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SectionHeader("Target")
            Card {
                VStack(spacing: 10) {
                    DetailRow(
                        label: "Repository",
                        value: state?.repository.slug ?? RepositoryReference.homelab.slug
                    )
                    Divider().overlay(palette.border)
                    DetailRow(
                        label: "Branch",
                        value: state?.repository.defaultBranch ?? "main"
                    )
                    Divider().overlay(palette.border)
                    DetailRow(
                        label: "Last refresh",
                        value: state?.snapshot.lastRefreshedAt.map { RelativeTime.ago($0) } ?? "—"
                    )
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SectionHeader("How this app behaves")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Note(
                        symbol: "faceid",
                        title: "Writes are behind Face ID",
                        detail: "Triggering, cancelling and merging all deploy. Reads are not gated."
                    )
                    Note(
                        symbol: "network",
                        title: "Health and logs need the tailnet",
                        detail: "Prometheus and Loki are reachable over Tailscale only. "
                            + "Runs and pull requests work from anywhere."
                    )
                    Note(
                        symbol: "clock.arrow.circlepath",
                        title: "Widgets refresh when iOS allows",
                        detail: "A widget is an ambient indicator, not an alert — "
                            + "the refresh interval is a hint the system may honour late."
                    )
                }
            }
        }
    }

    private var signOut: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SectionHeader("Session")
            Button {
                isConfirmingSignOut = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                    Text("Sign out")
                        .font(Typeface.body)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(palette.negative)
                .padding(Metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .fill(palette.negative.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .strokeBorder(palette.negative.opacity(0.25), lineWidth: Metrics.hairline)
                )
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Sign out of GitHub?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await session.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The token is removed from the Keychain. The widgets keep showing "
                    + "their last reading until they next refresh.")
            }
        }
    }
}

private struct DetailRow: View {
    @Environment(\.palette) private var palette

    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct Note: View {
    @Environment(\.palette) private var palette

    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
