import AIBankCore
import SwiftUI

/// The landing screen: a summary and every account.
struct AccountsView: View {
    let store: AppStore
    let customer: Customer

    private var accounts: AccountsState { store.state.accounts }

    var body: some View {
        NavigationStack(path: Binding(get: { accounts.path }, set: { store.send(.accounts(.pathChanged($0))) })) {
            ScrollView {
                LoadStateView(state: accounts.accounts, retry: { store.send(.accounts(.loadRequested)) }) { overview in
                    VStack(spacing: 20) {
                        summary(overview)
                        section("Everyday banking", overview.depositAccounts)
                        if !overview.creditAccounts.isEmpty { section("Credit", overview.creditAccounts) }
                    }
                    .padding(16)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Hi, \(customer.givenName)")
            .refreshable { store.send(.accounts(.loadRequested)) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section(customer.fullName) {
                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                store.send(.signOutTapped(now: .now))
                            }
                        }
                    } label: {
                        Avatar(initials: customer.initials, size: 32)
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .detail(let id): AccountDetailView(store: store, accountID: id)
                case .transactions(let id): TransactionsView(store: store, accountID: id)
                }
            }
        }
    }

    private func summary(_ overview: AccountsOverview) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
                MoneyText(money: overview.netWorth).font(.system(.largeTitle, design: .rounded, weight: .bold))
                HStack {
                    stat("Deposits", overview.totalDeposits)
                    Divider().frame(height: 32)
                    stat("Owed", overview.totalOwed)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ money: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            MoneyText(money: money).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, _ accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    Button { store.send(.accounts(.accountSelected(account.id))) } label: {
                        AccountRow(account: account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account-\(account.id.rawValue)")
                    if index < accounts.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: account.kind.symbolName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName).font(.body.weight(.medium))
                Text("\(account.kind.title) \(account.number.masked)").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(money: account.balance).font(.body.weight(.semibold))
                Text(account.kind.isCredit ? "Balance owing" : "Available \(account.availableFunds.formatted)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }
}
