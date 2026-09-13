import HomelabCore
import SwiftUI

struct SignInView: View {
    let message: String?

    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

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

                Spacer()

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
                    .opacity(session.configuration.isConfigured ? 1 : 0.4)

                    Text("A code appears next; type it into github.com on any device.")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
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

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Text("Enter this code on GitHub")
                    .font(Typeface.headline)
                    .foregroundStyle(palette.textPrimary)

                Text(grant.userCode)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .tracking(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: Metrics.hairline)
                    )

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

                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini).tint(palette.textTertiary)
                    Text("Waiting for authorisation…")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
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
