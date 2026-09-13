import Foundation
import HomelabCore
import LocalAuthentication

/// Face ID (or the passcode) in front of every write, and in front of nothing
/// else. See ADR-0004: the macOS app could hold no credential at all, and this
/// one has to, so the mitigation is that the credential cannot be *used* to
/// deploy by whoever is holding the unlocked phone.
///
/// `deviceOwnerAuthentication` rather than `...WithBiometrics` deliberately:
/// falling back to the passcode keeps the app usable with a wet thumb or a
/// mask, and the threat here is a borrowed phone, not a determined attacker
/// who already knows the passcode.
struct BiometricWriteAuthorisation: WriteAuthorising {
    func authorise(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set at all. Refusing would brick the app's write half
            // on a device the owner has deliberately left unsecured; allowing it
            // matches what every other app on that device already does.
            return true
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            // A cancel lands here too, which is the common case and is not an
            // error worth surfacing — the user changed their mind.
            return false
        }
    }
}
