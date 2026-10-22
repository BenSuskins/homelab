import HomelabCore
import SwiftUI
import UIKit

struct SignInView: View {
    let message: String?

    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()

            ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(palette.accent)

                    Text("Homelab")
                        .font(Typeface.title)
                        .foregroundStyle(palette.textPrimary)

                    Text("Run the workflows, merge the pull requests, and watch the hosts.")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    if let message {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(message)
                                .font(Typeface.caption)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(palette.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                                .fill(palette.warning.opacity(0.1))
                        )
                    }

                    Button {
                        session.signIn()
                    } label: {
                        Text("Sign in with GitHub")
                            .font(Typeface.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                                    .fill(palette.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.configuration.isConfigured)
                    .frame(minHeight: 52)

                    if !session.configuration.isConfigured {
                        Text("GitHub sign in is not configured for this build.")
                            .font(Typeface.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("A code appears next; type it into github.com on any device.")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
            .padding(.vertical, 24)
            }
        }
    }
}

/// The device flow's middle step. The user code is the whole screen, because
/// the user is about to copy it onto another device by eye.
struct DeviceCodeView: View {
    let grant: DeviceCodeGrant

    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    @State private var hasCopied = false

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Text("Enter this code on GitHub")
                    .font(Typeface.headline)
                    .foregroundStyle(palette.textPrimary)

                // Tappable, because the next thing that happens is that you
                // leave for Safari and have to reproduce it there.
                Button {
                    UIPasteboard.general.string = grant.userCode
                    withAnimation { hasCopied = true }
                } label: {
                    VStack(spacing: 6) {
                        Text(grant.userCode)
                            .font(.largeTitle.monospaced().weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                            .tracking(3)

                        HStack(spacing: 4) {
                            Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9, weight: .bold))
                            Text(hasCopied ? "Copied" : "Tap to copy")
                                .font(Typeface.footnote)
                        }
                        .foregroundStyle(hasCopied ? palette.positive : palette.textTertiary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: Metrics.hairline)
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 56)
                .accessibilityLabel("Copy code \(grant.userCode)")

                Button {
                    openURL(grant.verificationURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                        Text("Open github.com/login/device")
                            .font(Typeface.body)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .fill(palette.accent)
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 52)

                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini).tint(palette.textTertiary)
                        Text("Waiting for authorisation…")
                            .font(Typeface.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    // The flow survives being backgrounded now, so a failed
                    // poll is worth a line rather than a trip back to sign-in.
                    Text(
                        session.authorisationNotice
                            ?? "Leaving the app is fine — this keeps waiting."
                    )
                    .font(Typeface.footnote)
                    .foregroundStyle(
                        session.authorisationNotice == nil
                            ? palette.textTertiary
                            : palette.warning
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Cancel") {
                    session.cancelSignIn()
                }
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 28)
        }
    }
}
