import AIBankCore
import SwiftUI

struct AccountDetailView: View {
    let store: AppStore
    let accountID: Account.ID

    private var account: Account? { store.state.accounts.overview?.account(accountID) }
    private var history: LoadState<TransactionHistory> { store.state.accounts.history(for: accountID) }

    var body: some View {
        ScrollView {
            if let account {
                VStack(spacing: 20) {
                    balanceCard(account)
                    detailsCard(account)
                    if account.kind.canSendETransfer || account.kind.canPayBills { actions(account) }
                    recentActivity
                }
                .padding(16)
            } else {
                ContentUnavailableView("Account not found", systemImage: "questionmark.folder")
            }
        }
        .background(Theme.canvas)
        .navigationTitle(account?.displayName ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.send(.accounts(.transactionsRequested(accountID))); store.send(.accounts(.loadRequested)) }
    }

    private func balanceCard(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(account.kind.isCredit ? "Amount owing" : "Current balance")
                    .font(.subheadline).foregroundStyle(.secondary)
                MoneyText(money: account.kind.isCredit ? account.amountOwed : account.balance)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("\(account.kind.title) \(account.number.masked)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detailsCard(_ account: Account) -> some View {
        Card {
            VStack(spacing: 12) {
                row("Available funds", account.availableFunds.formatted)
                if account.kind.isCredit { row("Credit limit", account.borrowingLimit.formatted) }
                else if account.borrowingLimit.isPositive { row("Overdraft protection", account.borrowingLimit.formatted) }
                if account.interestRateBasisPoints > 0 {
                    row(account.kind.isCredit ? "Interest rate" : "Interest rate (annual)", account.interestRatePercentText)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func actions(_ account: Account) -> some View {
        HStack(spacing: 12) {
            if account.kind.canSendETransfer {
                Button { store.send(.tabSelected(.interac)) } label: { Label("Send money", systemImage: "paperplane") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if account.kind.canPayBills {
                Button { store.send(.tabSelected(.bills)) } label: { Label("Pay a bill", systemImage: "doc.text") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent activity").font(.headline)
                Spacer()
                Button("See all") { store.send(.accounts(.allTransactionsTapped(accountID))) }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("seeAllTransactions")
            }
            .padding(.horizontal, 4)

            switch history {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            case .failed(let error):
                ErrorBanner(message: error.message)
            case .loaded(let h):
                if h.isEmpty {
                    Card { Text("No transactions yet.").foregroundStyle(.secondary) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(h.recent.enumerated()), id: \.element.id) { index, t in
                            TransactionRow(transaction: t)
                            if index < h.recent.count - 1 { Divider().padding(.leading, 68) }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    spendingCard(h)
                }
            }
        }
    }

    @ViewBuilder
    private func spendingCard(_ h: TransactionHistory) -> some View {
        let spending = Array(h.spendingByCategory().prefix(4))
        if let top = spending.first {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where the money went").font(.headline)
                    ForEach(spending, id: \.category) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category.title).font(.subheadline)
                                Spacer()
                                MoneyText(money: item.total).font(.subheadline)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Color.accentColor.opacity(0.15))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.accentColor)
                                            .frame(width: proxy.size.width * CGFloat(item.total.minorUnits) / CGFloat(max(top.total.minorUnits, 1)))
                                    }
                            }
                            .frame(height: 6)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: AIBankCore.Transaction

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: transaction.category.symbolName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(transaction.date.shortDay)
                    if transaction.status == .pending {
                        Text("Pending").padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange)
                    }
                    if let detail = transaction.detail { Text("· \(detail)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            MoneyText(money: transaction.amount, showsSign: true).font(.body.weight(.semibold))
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transaction.accessibilitySummary)
    }
}
