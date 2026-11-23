import AIBankCore
import AppIntents
import Observation

// When a tool runs while no one is signed in, the server refuses it. Rather than failing, the tool brings aiBank
// forward, waits for the person to sign in on the normal sign-in screen, and then tries once more.
//
// Every check still happens on the server: the gate only decides *when* to ask again.

extension AppIntent {
    /// Runs `work`. If the server says there is no session, asks the person to sign in in the app and runs it again.
    /// - Parameter reason: what the person is signing in for, finishing the sentence "Sign in to aiBank to …".
    func afterSigningIn<T: Sendable>(
        store: AppStore, reason: String, _ work: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as BankError where error == .notSignedIn || error == .sessionExpired {
            // Voice-only places (CarPlay, AirPods on the go) can't show the app; let the system say so.
            guard systemContext.currentMode.canContinueInForeground else {
                throw needsToContinueInForegroundError("Open aiBank and sign in to \(reason).")
            }
            await store.send(.serverEndedSession(error, now: .now))
            try await continueInForeground("Sign in to aiBank to \(reason).", alwaysConfirm: false)
            try await store.waitUntilSignedIn()
            return try await work()
        }
    }
}

extension AppStore {
    /// Suspends until the app reaches the signed-in phase. Ends with `CancellationError` if the system gives up
    /// on the intent first, for example when the person dismisses Siri.
    func waitUntilSignedIn() async throws {
        for await signedIn in Observations({ [self] in self.state.session.session != nil }) where signedIn {
            return
        }
        throw CancellationError()
    }
}
