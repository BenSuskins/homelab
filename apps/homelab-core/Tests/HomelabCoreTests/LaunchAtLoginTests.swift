import Foundation
import Testing
@testable import HomelabCore

@MainActor
@Suite("Launch at login")
struct LaunchAtLoginTests {
    private func makeState(
        loginItem: FakeLoginItemService,
        preference: LaunchAtLoginPreference = .temporary()
    ) -> AppState {
        AppState(
            client: GitHubClient(transport: FakeTransport(), repository: .homelab),
            repository: .homelab,
            cache: SnapshotCache(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("homelab-login-tests-\(UUID().uuidString)")
                    .appendingPathComponent("snapshot.json")
            ),
            notifier: RecordingNotifier(),
            loginItem: loginItem,
            launchAtLoginPreference: preference
        )
    }

    @Test("registers and remembers the intent when switched on")
    func switchingOnRegisters() {
        let loginItem = FakeLoginItemService(status: .disabled)
        let preference = LaunchAtLoginPreference.temporary()
        let state = makeState(loginItem: loginItem, preference: preference)

        state.setLaunchAtLogin(true)

        #expect(loginItem.writes == [.register])
        #expect(state.launchesAtLogin)
        #expect(preference.isRequested)
        #expect(state.launchAtLoginError == nil)
    }

    @Test("unregisters and forgets the intent when switched off")
    func switchingOffUnregisters() {
        let loginItem = FakeLoginItemService(status: .enabled)
        let preference = LaunchAtLoginPreference.temporary()
        let state = makeState(loginItem: loginItem, preference: preference)
        state.setLaunchAtLogin(true)

        state.setLaunchAtLogin(false)

        #expect(loginItem.writes == [.register, .unregister])
        #expect(state.launchesAtLogin == false)
        #expect(preference.isRequested == false)
    }

    @Test("reports a failed registration without claiming the toggle is on")
    func failedRegistrationSurfacesAnError() {
        let loginItem = FakeLoginItemService(
            status: .disabled,
            registrationFailure: LoginItemFailure(message: "Operation not permitted")
        )
        let preference = LaunchAtLoginPreference.temporary()
        let state = makeState(loginItem: loginItem, preference: preference)

        state.setLaunchAtLogin(true)

        #expect(state.launchesAtLogin == false)
        #expect(state.launchAtLoginError == "Operation not permitted")
        #expect(preference.isRequested == false)
    }

    @Test("re-registers at launch when a rebuild dropped the registration")
    func reassertsRegistrationAtLaunch() {
        let preference = LaunchAtLoginPreference.temporary()
        preference.record(true)
        // `make bundle` ad-hoc signs, so a rebuilt app can arrive with the
        // registration silently gone even though the user asked for it.
        let loginItem = FakeLoginItemService(status: .disabled)
        let state = makeState(loginItem: loginItem, preference: preference)

        state.reconcileLaunchAtLogin()

        #expect(loginItem.writes == [.register])
        #expect(state.launchesAtLogin)
    }

    @Test("does not register at launch when the user never asked for it")
    func doesNotRegisterUnasked() {
        let loginItem = FakeLoginItemService(status: .disabled)
        let state = makeState(loginItem: loginItem)

        state.reconcileLaunchAtLogin()

        #expect(loginItem.writes.isEmpty)
        #expect(state.launchesAtLogin == false)
    }

    @Test("leaves an approval the user must give in System Settings alone")
    func doesNotFightRequiresApproval() {
        let preference = LaunchAtLoginPreference.temporary()
        preference.record(true)
        let loginItem = FakeLoginItemService(status: .requiresApproval)
        let state = makeState(loginItem: loginItem, preference: preference)

        state.reconcileLaunchAtLogin()

        #expect(loginItem.writes.isEmpty)
        #expect(state.loginItemStatus == .requiresApproval)
        #expect(state.launchesAtLogin == false)
    }

    @Test("tries anyway when macOS reports the app as not found")
    func attemptsRegistrationWhenUnavailable() {
        let preference = LaunchAtLoginPreference.temporary()
        preference.record(true)
        // `SMAppService.mainApp` reports `.notFound` in cases where registering
        // nonetheless succeeds, so the attempt is the truth, not the status.
        let loginItem = FakeLoginItemService(status: .unavailable)
        let state = makeState(loginItem: loginItem, preference: preference)

        state.reconcileLaunchAtLogin()

        #expect(loginItem.writes == [.register])
        #expect(state.launchesAtLogin)
    }

    @Test("reports what macOS said when an unavailable app really cannot register")
    func explainsAnImpossibleRegistration() {
        let loginItem = FakeLoginItemService(
            status: .unavailable,
            registrationFailure: LoginItemFailure(message: "The operation couldn’t be completed.")
        )
        let state = makeState(loginItem: loginItem)

        state.setLaunchAtLogin(true)

        // Never a switch that refuses to move with no explanation.
        #expect(state.launchesAtLogin == false)
        #expect(state.launchAtLoginHint == "The operation couldn’t be completed.")
    }

    @Test("explains an approval only System Settings can give")
    func explainsRequiresApproval() {
        let loginItem = FakeLoginItemService(status: .requiresApproval)
        let state = makeState(loginItem: loginItem)

        state.reconcileLaunchAtLogin()

        #expect(state.launchAtLoginHint != nil)
    }

    @Test("adopts a registration made outside the app")
    func adoptsExternalRegistration() {
        let loginItem = FakeLoginItemService(status: .enabled)
        let preference = LaunchAtLoginPreference.temporary()
        let state = makeState(loginItem: loginItem, preference: preference)

        state.reconcileLaunchAtLogin()

        #expect(loginItem.writes.isEmpty)
        #expect(state.launchesAtLogin)
        #expect(preference.isRequested)
    }
}

@Suite("LaunchAtLoginPreference")
struct LaunchAtLoginPreferenceTests {
    @Test("defaults to off and round-trips what was recorded")
    func roundTripsIntent() {
        let preference = LaunchAtLoginPreference.temporary()

        #expect(preference.isRequested == false)

        preference.record(true)
        #expect(preference.isRequested)

        preference.record(false)
        #expect(preference.isRequested == false)
    }
}
