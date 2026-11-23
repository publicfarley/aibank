import AIBankCore
import SwiftUI

struct TransactionsView: View {
    let store: AppStore
    let accountID: Account.ID

    private var accounts: AccountsState { store.state.accounts }
    private var filter: TransactionFilter { accounts.filter }

    private var filterBinding: Binding<TransactionFilter> {
        Binding(get: { store.state.accounts.filter }, set: { store.send(.accounts(.filterChanged($0))) })
    }

    var body: some View {
        List {
            switch accounts.history(for: accountID) {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load transactions", systemImage: "wifi.exclamationmark")
                } description: { Text(error.message) } actions: {
                    Button("Try Again") { store.send(.accounts(.transactionsRequested(accountID))) }
                }
                .listRowBackground(Color.clear)
            case .loaded(let history):
                let shown = history.filtered(filter)
                Section {
                    Picker("Show", selection: filterBinding.direction) {
                        ForEach(TransactionDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                    totals(shown)
                }

                if shown.isEmpty {
                    ContentUnavailableView.search(text: filter.searchText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(shown.grouped(calendar: accounts.calendar)) { group in
                        Section {
                            ForEach(group.transactions) { t in
                                TransactionRow(transaction: t)
                                    .listRowInsets(.init())
                            }
                        } header: {
                            HStack {
                                Text(group.day.formatted(.dateTime.weekday(.wide).month().day()))
                                Spacer()
                                MoneyText(money: group.net, showsSign: true).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: filterBinding.searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: filterBinding.category) {
                        Text("All categories").tag(TransactionCategory?.none)
                        ForEach(TransactionCategory.allCases, id: \.self) {
                            Label($0.title, systemImage: $0.symbolName).tag(TransactionCategory?.some($0))
                        }
                    }
                } label: {
                    Image(systemName: filter.category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by category")
            }
        }
        .refreshable { store.send(.accounts(.transactionsRequested(accountID))) }
    }

    private func totals(_ h: TransactionHistory) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Money in").font(.caption).foregroundStyle(.secondary)
                MoneyText(money: h.moneyIn, showsSign: true).font(.headline)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Money out").font(.caption).foregroundStyle(.secondary)
                MoneyText(money: h.moneyOut).font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
