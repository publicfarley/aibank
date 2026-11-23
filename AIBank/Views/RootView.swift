import AIBankCore
import SwiftUI

struct RootView: View {
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.state.session.phase {
            case .signedOut:
                SignInView(store: store)
            case .signedIn(let session):
                MainTabView(store: store, customer: session.customer)
            }
        }
        .animation(.default, value: store.state.session.phase)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.send(.becameActive(now: .now))
            case .background: store.send(.movedToBackground(now: .now))
            default: break
            }
        }
    }
}

struct MainTabView: View {
    let store: AppStore
    let customer: Customer

    var body: some View {
        TabView(selection: Binding(get: { store.state.selectedTab }, set: { store.send(.tabSelected($0)) })) {
            Tab(AppTab.accounts.shortTitle, systemImage: AppTab.accounts.symbolName, value: AppTab.accounts) {
                AccountsView(store: store, customer: customer)
            }
            Tab(AppTab.interac.shortTitle, systemImage: AppTab.interac.symbolName, value: AppTab.interac) {
                ETransferView(store: store)
            }
            Tab(AppTab.bills.shortTitle, systemImage: AppTab.bills.symbolName, value: AppTab.bills) {
                BillPayView(store: store)
            }
            Tab(AppTab.atms.shortTitle, systemImage: AppTab.atms.symbolName, value: AppTab.atms) {
                ATMFinderView(store: store)
            }
        }
    }
}
