import Foundation

public enum AccountRoute: Hashable, Sendable {
    case detail(Account.ID)
    case transactions(Account.ID)
}

public struct AccountsState: Equatable, Sendable {
    public var accounts: LoadState<AccountsOverview> = .idle
    public var transactions: [Account.ID: LoadState<TransactionHistory>] = [:]
    public var path: [AccountRoute] = []
    public var filter = TransactionFilter()
    public var calendar: Calendar

    public init(calendar: Calendar) { self.calendar = calendar }

    public var overview: AccountsOverview? { accounts.value }

    public func history(for id: Account.ID) -> LoadState<TransactionHistory> { transactions[id] ?? .idle }

    /// Transactions loaded so far, across accounts. Used for rules like the e-Transfer daily limit.
    public var knownTransactions: [Transaction] {
        transactions.values.flatMap { $0.value?.transactions ?? [] }
    }
}

public enum AccountsAction: Sendable {
    case loadRequested
    case loaded(Result<[Account], BankError>)
    case accountSelected(Account.ID)
    case pathChanged([AccountRoute])
    case allTransactionsTapped(Account.ID)
    case transactionsRequested(Account.ID)
    case transactionsLoaded(Account.ID, Result<[Transaction], BankError>)
    case filterChanged(TransactionFilter)
    /// Deep link (Siri, Spotlight, Shortcuts) straight to an account.
    case openAccount(Account.ID, showingTransactions: Bool)

    var failure: BankError? {
        switch self {
        case .loaded(.failure(let e)), .transactionsLoaded(_, .failure(let e)): e
        default: nil
        }
    }
}

enum AccountsFeature {
    static func reduce(_ state: AccountsState, _ action: AccountsAction) -> Reduced<AccountsState, BankEffect> {
        var s = state
        switch action {
        case .loadRequested:
            if s.accounts.value == nil { s.accounts = .loading }
            return Reduced(s, [.loadAccounts])

        case .loaded(.success(let accounts)):
            s.accounts = .loaded(AccountsOverview(accounts: accounts))
            return Reduced(s)

        case .loaded(.failure(let error)):
            // Keep showing stale data if we have it; only surface the error when we have nothing.
            if s.accounts.value == nil { s.accounts = .failed(error) }
            return Reduced(s)

        case .accountSelected(let id):
            s.path = [.detail(id)]
            s.filter = TransactionFilter()
            let effects = beginLoadingTransactions(&s, id)
            return Reduced(s, effects)

        case .openAccount(let id, let showing):
            s.path = showing ? [.detail(id), .transactions(id)] : [.detail(id)]
            s.filter = TransactionFilter()
            let effects = beginLoadingTransactions(&s, id)
            return Reduced(s, effects)

        case .pathChanged(let path):
            s.path = path
            if !path.contains(where: { if case .transactions = $0 { true } else { false } }) {
                s.filter = TransactionFilter()
            }
            return Reduced(s)

        case .allTransactionsTapped(let id):
            s.path.append(.transactions(id))
            return Reduced(s)

        case .transactionsRequested(let id):
            let effects = beginLoadingTransactions(&s, id)
            return Reduced(s, effects)

        case .transactionsLoaded(let id, .success(let list)):
            s.transactions[id] = .loaded(TransactionHistory(list))
            return Reduced(s)

        case .transactionsLoaded(let id, .failure(let error)):
            if s.transactions[id]?.value == nil { s.transactions[id] = .failed(error) }
            return Reduced(s)

        case .filterChanged(let filter):
            s.filter = filter
            return Reduced(s)
        }
    }

    private static func beginLoadingTransactions(_ s: inout AccountsState, _ id: Account.ID) -> [BankEffect] {
        if s.transactions[id]?.value == nil { s.transactions[id] = .loading }
        return [.loadTransactions(id)]
    }
}
