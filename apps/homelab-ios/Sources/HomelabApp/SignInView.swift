import HomelabCore
import SwiftUI

struct SignInView: View {
    let message: String?

    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Homelab")
                .font(.largeTitle.weight(.semibold))

            Text("Sign in with GitHub to run the workflows and merge pull requests.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button("Sign in with GitHub") {
                session.signIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!AppConfiguration.isConfigured)

            Text("A code appears next; type it into github.com on any device.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }
}

/// The device flow's middle step. The user code is the whole screen, because
/// the user is about to copy it onto another device by eye.
struct DeviceCodeView: View {
    let grant: DeviceCodeGrant

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Text("Enter this code on GitHub")
                .font(.headline)

            Text(grant.userCode)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.quaternary, in: .rect(cornerRadius: 12))

            Button {
                openURL(grant.verificationURL)
            } label: {
                Label("Open github.com/login/device", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)

            ProgressView("Waiting for authorisation…")
                .font(.footnote)

            Button("Cancel", role: .cancel) {
                session.cancelSignIn()
            }
            .font(.footnote)
        }
        .padding(32)
    }
}
