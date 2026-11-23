import AIBankBoundary
import AIBankCore
import AppIntents
import SwiftUI

@main
struct AIBankApp: App {
    private let store: AppStore

    init() {
        // The live environment: a fake backend that pretends to be a server, persisted so changes made by
        // Siri while the app is off screen are still there on next launch.
        let client = FakeBackend.client(persistence: .file(Self.serverStateURL))
        let environment = BankEnvironment(client: client, now: { Date() })
        let store = AppStore(initial: AppFeature.State(now: .now, calendar: .current), environment: environment)
        self.store = store

        // Intents run cold, so everything they need is registered here, on every launch, never from a view.
        AppDependencyManager.shared.add(dependency: client)
        AppDependencyManager.shared.add(dependency: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }

    private static var serverStateURL: URL {
        URL.applicationSupportDirectory.appending(path: "aibank-fake-server.json")
    }
}
