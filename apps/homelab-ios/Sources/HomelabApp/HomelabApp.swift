import HomelabCore
import SwiftUI
import WidgetKit

@main
struct HomelabApp: App {
    @State private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    /// Built in `init()` rather than as a default value on the property.
    ///
    /// The expression constructs three `@MainActor` types, one nested inside
    /// another, and as a stored-property initializer that crashed the Swift
    /// compiler outright — `swift-frontend` stack-dumped in SILGen, "While
    /// silgen emitStoredPropertyInitialization ... variable initialization
    /// expression of HomelabApp._session". There is no diagnostic to fix,
    /// only a code path to avoid. An explicit initializer runs the same code
    /// in the App's own `@MainActor` context and does not go near it.
    init() {
        _session = State(initialValue: Self.makeSession())
    }

    private static func makeSession() -> Session {
        let appGroup = HomelabConfiguration.iOS.appGroup ?? ""

        return Session(
            configuration: .iOS,
            tokens: KeychainTokenStore(
                service: HomelabConfiguration.iOS.keychainService,
                accessGroup: HomelabConfiguration.iOS.keychainAccessGroup
            ),
            cache: SnapshotCache(appGroup: appGroup),
            // No notifier: a suspended iOS app never sees the failure, so the
            // widgets are the ambient signal instead. See ADR-0005.
            writeAuthorisation: BiometricWriteAuthorisation(),
            // The health widget cannot reach Prometheus unless the phone
            // happens to be on the tailnet when iOS decides to refresh it, so
            // the app writes every reading it takes to the App Group and the
            // widget falls back to that. It is then as fresh as your last
            // visit, which is honest and is what the widget says on its face.
            healthMonitor: HealthMonitor(cache: HealthCache(appGroup: appGroup))
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.restore() }
                .onChange(of: scenePhase) { _, phase in
                    // The polling loop only runs while foregrounded, because
                    // iOS suspends the process seconds after backgrounding
                    // whatever we intend (ADR-0005).
                    switch phase {
                    case .active:
                        session.appState?.start()
                        // Coming back from Safari with the code typed in is the
                        // expected path through sign-in, and being suspended
                        // over there stops the poll mid-flight. Pick it up
                        // again straight away rather than after the interval.
                        session.resumeSignIn()
                    case .background, .inactive:
                        session.appState?.stop()
                        // Hand the widget the freshest snapshot on the way out;
                        // this is the moment it is most likely to be looked at.
                        WidgetCenter.shared.reloadAllTimelines()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
