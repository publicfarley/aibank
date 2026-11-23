import Foundation

public enum TransactionKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case purchase, refund, payroll, deposit, eTransferSent, eTransferReceived
    case billPayment, atmWithdrawal, atmDeposit, transferIn, transferOut, fee, interest
}

public enum TransactionCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case groceries, dining, transport, shopping, utilities, housing
    case health, entertainment, income, transfers, cash, fees, other

    public var title: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .utilities: "Bills & Utilities"
        case .housing: "Housing"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .income: "Income"
        case .transfers: "Transfers"
        case .cash: "Cash"
        case .fees: "Fees & Interest"
        case .other: "Other"
        }
    }
}

public enum TransactionStatus: String, Sendable, Equatable, Hashable {
    case pending, posted
}

public struct Transaction: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Transaction>

    public let id: ID
    public let accountID: Account.ID
    public let kind: TransactionKind
    /// Signed from the account's point of view: negative leaves the account, positive enters it.
    public let amount: Money
    public let date: Date
    public let status: TransactionStatus
    public let title: String
    public let detail: String?
    public let category: TransactionCategory

    public init(id: ID, accountID: Account.ID, kind: TransactionKind, amount: Money, date: Date,
                status: TransactionStatus = .posted, title: String, detail: String? = nil,
                category: TransactionCategory) {
        self.id = id
        self.accountID = accountID
        self.kind = kind
        self.amount = amount
        self.date = date
        self.status = status
        self.title = title
        self.detail = detail
        self.category = category
    }

    public var isCredit: Bool { amount.isPositive }
    public var isDebit: Bool { amount.isNegative }

    public var accessibilitySummary: String {
        "\(title), \(isCredit ? "deposit of" : "payment of") \(amount.magnitude.formatted)\(status == .pending ? ", pending" : "")"
    }
}

public enum TransactionDirection: String, Sendable, Equatable, CaseIterable {
    case all, moneyIn, moneyOut

    public var title: String {
        switch self {
        case .all: "All"
        case .moneyIn: "Money In"
        case .moneyOut: "Money Out"
        }
    }
}

public struct TransactionFilter: Sendable, Equatable {
    public var searchText: String
    public var direction: TransactionDirection
    public var category: TransactionCategory?

    public init(searchText: String = "", direction: TransactionDirection = .all, category: TransactionCategory? = nil) {
        self.searchText = searchText
        self.direction = direction
        self.category = category
    }

    public var isActive: Bool { !searchText.isEmpty || direction != .all || category != nil }

    public func matches(_ t: Transaction) -> Bool {
        switch direction {
        case .all: break
        case .moneyIn: if !t.isCredit { return false }
        case .moneyOut: if !t.isDebit { return false }
        }
        if let category, t.category != category { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return true }
        return t.title.localizedCaseInsensitiveContains(query)
            || (t.detail?.localizedCaseInsensitiveContains(query) ?? false)
            || t.category.title.localizedCaseInsensitiveContains(query)
    }
}

public struct TransactionDayGroup: Sendable, Equatable, Identifiable {
    public let day: Date
    public let transactions: [Transaction]
    public var id: Date { day }
    public var net: Money { transactions.reduce(.zero()) { $0 + $1.amount } }
}

/// A newest-first ledger with the queries a statement screen needs.
public struct TransactionHistory: Sendable, Equatable {
    public let transactions: [Transaction]

    public init(_ transactions: [Transaction]) {
        self.transactions = transactions.sorted { ($0.date, $0.id.rawValue) > ($1.date, $1.id.rawValue) }
    }

    public var isEmpty: Bool { transactions.isEmpty }
    public var recent: [Transaction] { Array(transactions.prefix(5)) }

    public func filtered(_ filter: TransactionFilter) -> TransactionHistory {
        filter.isActive ? TransactionHistory(transactions.filter(filter.matches)) : self
    }

    public var moneyIn: Money { transactions.filter(\.isCredit).reduce(.zero()) { $0 + $1.amount } }
    public var moneyOut: Money { transactions.filter(\.isDebit).reduce(.zero()) { $0 + $1.amount.magnitude } }

    /// Spending per category, largest first. Debits only.
    public func spendingByCategory() -> [(category: TransactionCategory, total: Money)] {
        var totals: [TransactionCategory: Money] = [:]
        for t in transactions where t.isDebit {
            totals[t.category, default: .zero()] = totals[t.category, default: .zero()] + t.amount.magnitude
        }
        return totals.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    public func grouped(calendar: Calendar) -> [TransactionDayGroup] {
        let buckets = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { TransactionDayGroup(day: $0, transactions: buckets[$0] ?? []) }
    }

    /// Total of e-Transfers sent on the same calendar day as `now` (used for daily limits).
    public func eTransfersSent(on now: Date, calendar: Calendar) -> Money {
        transactions
            .filter { $0.kind == .eTransferSent && calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(.zero()) { $0 + $1.amount.magnitude }
    }
}
