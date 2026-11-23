import Foundation

public enum AccountKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case chequing, savings, tfsa, creditCard, lineOfCredit

    public var title: String {
        switch self {
        case .chequing: "Chequing"
        case .savings: "Savings"
        case .tfsa: "TFSA"
        case .creditCard: "Credit Card"
        case .lineOfCredit: "Line of Credit"
        }
    }

    /// Credit products carry a negative balance when money is owed.
    public var isCredit: Bool { self == .creditCard || self == .lineOfCredit }

    /// Where money may be sent from via Interac e-Transfer.
    public var canSendETransfer: Bool { self == .chequing || self == .savings }

    /// Where bill payments may be funded from.
    public var canPayBills: Bool { self == .chequing || self == .savings }

    /// Display ordering on the landing screen.
    public var sortOrder: Int {
        switch self {
        case .chequing: 0
        case .savings: 1
        case .tfsa: 2
        case .creditCard: 3
        case .lineOfCredit: 4
        }
    }
}

/// A validated account number. Only the masked form is ever displayed.
public struct AccountNumber: Sendable, Equatable, Hashable {
    private let digits: String

    public init?(_ raw: String) {
        let cleaned = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard (7...19).contains(cleaned.count), cleaned.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        self.digits = cleaned
    }

    public var last4: String { String(digits.suffix(4)) }
    public var masked: String { "•••• \(last4)" }
    /// The full number. Reserved for the boundary; views and intents should use `masked`.
    public var unmasked: String { digits }
}

public struct Account: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Account>

    public let id: ID
    public let kind: AccountKind
    public let nickname: String
    public let number: AccountNumber
    /// Ledger balance. Positive = money you have. Negative = money you owe (credit products).
    public let balance: Money
    /// Overdraft room on chequing, credit limit on credit products, otherwise zero.
    public let borrowingLimit: Money
    /// Annual interest rate in basis points (e.g. 250 = 2.50 %).
    public let interestRateBasisPoints: Int

    public init(id: ID, kind: AccountKind, nickname: String, number: AccountNumber, balance: Money,
                borrowingLimit: Money = .zero(), interestRateBasisPoints: Int = 0) {
        self.id = id
        self.kind = kind
        self.nickname = nickname
        self.number = number
        self.balance = balance
        self.borrowingLimit = borrowingLimit
        self.interestRateBasisPoints = interestRateBasisPoints
    }

    public var currency: Currency { balance.currency }

    /// What can actually be spent right now.
    public var availableFunds: Money { balance + borrowingLimit }

    /// For credit products, the amount owed (always >= 0). For deposit accounts, zero.
    public var amountOwed: Money { kind.isCredit && balance.isNegative ? balance.magnitude : .zero(currency) }

    public var interestRatePercentText: String {
        let whole = interestRateBasisPoints / 100
        let frac = interestRateBasisPoints % 100
        return "\(whole).\(frac < 10 ? "0" : "")\(frac)%"
    }

    public var displayName: String { nickname.isEmpty ? kind.title : nickname }

    public var accessibilitySummary: String {
        "\(displayName), \(kind.title) ending \(number.last4), balance \(balance.formatted)"
    }

    /// Can `amount` leave this account without exceeding available funds?
    public func canCover(_ amount: Money) -> Bool {
        amount.currency == currency && amount <= availableFunds
    }

    /// A copy of the account after a ledger entry posts.
    public func applying(_ amount: Money) -> Account {
        Account(id: id, kind: kind, nickname: nickname, number: number, balance: balance + amount,
                borrowingLimit: borrowingLimit, interestRateBasisPoints: interestRateBasisPoints)
    }
}

/// Everything the landing screen needs to summarise a customer's finances.
public struct AccountsOverview: Sendable, Equatable {
    public let accounts: [Account]

    public init(accounts: [Account]) {
        self.accounts = accounts.sorted {
            ($0.kind.sortOrder, $0.nickname) < ($1.kind.sortOrder, $1.nickname)
        }
    }

    public var totalDeposits: Money {
        accounts.filter { !$0.kind.isCredit }.reduce(.zero()) { $0 + $1.balance }
    }

    public var totalOwed: Money {
        accounts.filter { $0.kind.isCredit }.reduce(.zero()) { $0 + $1.amountOwed }
    }

    public var netWorth: Money { totalDeposits - totalOwed }

    public var depositAccounts: [Account] { accounts.filter { !$0.kind.isCredit } }
    public var creditAccounts: [Account] { accounts.filter(\.kind.isCredit) }
    public var eTransferSources: [Account] { accounts.filter { $0.kind.canSendETransfer } }
    public var billPaySources: [Account] { accounts.filter { $0.kind.canPayBills } }

    public func account(_ id: Account.ID) -> Account? { accounts.first { $0.id == id } }
}
