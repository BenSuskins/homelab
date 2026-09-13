import HomelabCore
import SwiftUI
import WidgetKit

@main
struct HomelabApp: App {
    @State private var session = Session(
        configuration: .iOS,
        tokens: KeychainTokenStore(
            service: HomelabConfiguration.iOS.keychainService,
            accessGroup: HomelabConfiguration.iOS.keychainAccessGroup
        ),
        cache: SnapshotCache(appGroup: HomelabConfiguration.iOS.appGroup ?? ""),
        // No notifier: a suspended iOS app never sees the failure, so the
        // widget is the ambient signal instead. See ADR-0005.
        writeAuthorisation: BiometricWriteAuthorisation()
    )
    @Environment(\.scenePhase) private var scenePhase

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
