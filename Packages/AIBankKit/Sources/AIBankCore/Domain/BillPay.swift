import Foundation

public enum BillerCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case utilities, telecom, insurance, creditCard, tax, housing, other

    public var title: String {
        switch self {
        case .utilities: "Utilities"
        case .telecom: "Telecom"
        case .insurance: "Insurance"
        case .creditCard: "Credit Cards"
        case .tax: "Taxes"
        case .housing: "Housing"
        case .other: "Other"
        }
    }
}

public struct Biller: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Biller>

    public let id: ID
    public let name: String
    public let category: BillerCategory
    /// Customer account numbers at this company have a known length.
    public let accountNumberLength: ClosedRange<Int>

    public init(id: ID, name: String, category: BillerCategory, accountNumberLength: ClosedRange<Int>) {
        self.id = id
        self.name = name
        self.category = category
        self.accountNumberLength = accountNumberLength
    }
}

/// A biller the customer has set up, with their account number at that company.
public struct Payee: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Payee>

    public let id: ID
    public let biller: Biller
    public let accountNumber: String
    public let nickname: String?
    public let lastPayment: Money?

    public init(id: ID, biller: Biller, accountNumber: String, nickname: String?, lastPayment: Money?) {
        self.id = id
        self.biller = biller
        self.accountNumber = accountNumber
        self.nickname = nickname
        self.lastPayment = lastPayment
    }

    public var displayName: String { nickname ?? biller.name }
    public var maskedAccountNumber: String { "•••• \(accountNumber.suffix(4))" }
}

public enum BillPaymentIssue: Sendable, Equatable {
    case noSourceAccount
    case ineligibleSource
    case noPayee
    case invalidAmount
    case insufficientFunds(available: Money)
    case dateInPast
    case dateTooFarAhead

    public var message: String {
        switch self {
        case .noSourceAccount: "Choose an account to pay from."
        case .ineligibleSource: "Bills can only be paid from chequing or savings accounts."
        case .noPayee: "Choose who you are paying."
        case .invalidAmount: "Enter an amount, like 84.50."
        case .insufficientFunds(let a): "That is more than the \(a.formatted) available in this account."
        case .dateInPast: "Choose today or a future date."
        case .dateTooFarAhead: "Payments can be scheduled up to one year ahead."
        }
    }
}

public struct BillPayment: Sendable, Equatable {
    public let source: Account.ID
    public let payee: Payee
    public let amount: Money
    /// Start of the day the payment should be made.
    public let payOn: Date
    public let isImmediate: Bool

    fileprivate init(source: Account.ID, payee: Payee, amount: Money, payOn: Date, isImmediate: Bool) {
        self.source = source
        self.payee = payee
        self.amount = amount
        self.payOn = payOn
        self.isImmediate = isImmediate
    }
}

public enum BillPaymentStatus: String, Sendable, Equatable {
    case completed, scheduled
}

public struct BillPaymentReceipt: Sendable, Equatable {
    public let confirmationNumber: String
    public let payment: BillPayment
    public let status: BillPaymentStatus
    public let processedAt: Date
    public let sourceBalanceAfter: Money

    public init(confirmationNumber: String, payment: BillPayment, status: BillPaymentStatus,
                processedAt: Date, sourceBalanceAfter: Money) {
        self.confirmationNumber = confirmationNumber
        self.payment = payment
        self.status = status
        self.processedAt = processedAt
        self.sourceBalanceAfter = sourceBalanceAfter
    }
}

public struct BillPaymentDraft: Sendable, Equatable {
    public var sourceID: Account.ID?
    public var payeeID: Payee.ID?
    public var amountText: String
    /// Nil means "pay now".
    public var scheduledDate: Date?

    public init(sourceID: Account.ID? = nil, payeeID: Payee.ID? = nil, amountText: String = "", scheduledDate: Date? = nil) {
        self.sourceID = sourceID
        self.payeeID = payeeID
        self.amountText = amountText
        self.scheduledDate = scheduledDate
    }

    public func validate(accounts: [Account], payees: [Payee], now: Date, calendar: Calendar)
        -> Result<BillPayment, ValidationFailure<BillPaymentIssue>>
    {
        var issues: [BillPaymentIssue] = []
        let today = calendar.startOfDay(for: now)

        let source = sourceID.flatMap { id in accounts.first { $0.id == id } }
        if source == nil { issues.append(.noSourceAccount) }
        else if let source, !source.kind.canPayBills { issues.append(.ineligibleSource) }

        let payee = payeeID.flatMap { id in payees.first { $0.id == id } }
        if payee == nil { issues.append(.noPayee) }

        let amount = Money(string: amountText)
        if let amount, amount.isPositive {
            if let source, source.kind.canPayBills, !source.canCover(amount) {
                issues.append(.insufficientFunds(available: source.availableFunds))
            }
        } else {
            issues.append(.invalidAmount)
        }

        let payOn = calendar.startOfDay(for: scheduledDate ?? now)
        if payOn < today { issues.append(.dateInPast) }
        if let limit = calendar.date(byAdding: .year, value: 1, to: today), payOn > limit {
            issues.append(.dateTooFarAhead)
        }

        guard issues.isEmpty, let source, let payee, let amount else { return .failure(ValidationFailure(issues)) }
        return .success(BillPayment(source: source.id, payee: payee, amount: amount, payOn: payOn,
                                    isImmediate: payOn == today))
    }
}
