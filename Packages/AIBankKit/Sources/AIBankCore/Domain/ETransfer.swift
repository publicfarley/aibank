import Foundation

public struct EmailAddress: Sendable, Equatable, Hashable {
    public let value: String

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty,
              parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !text.contains(" ") else { return nil }
        self.value = text
    }
}

public struct Recipient: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Recipient>

    public let id: ID
    public let name: String
    public let email: EmailAddress
    /// With Autodeposit the money lands directly; otherwise a security question protects it.
    public let hasAutodeposit: Bool

    public init(id: ID, name: String, email: EmailAddress, hasAutodeposit: Bool) {
        self.id = id
        self.name = name
        self.email = email
        self.hasAutodeposit = hasAutodeposit
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

public struct SecurityChallenge: Sendable, Equatable {
    public let question: String
    public let answer: String
}

public struct ETransferLimits: Sendable, Equatable {
    public let minimum: Money
    public let perTransaction: Money
    public let perDay: Money
    public let maxMessageLength: Int

    public init(minimum: Money, perTransaction: Money, perDay: Money, maxMessageLength: Int) {
        self.minimum = minimum
        self.perTransaction = perTransaction
        self.perDay = perDay
        self.maxMessageLength = maxMessageLength
    }

    public static let standard = ETransferLimits(
        minimum: .cad(1), perTransaction: .cad(300_000), perDay: .cad(1_000_000), maxMessageLength: 400)
}

public enum ETransferIssue: Sendable, Equatable {
    case noSourceAccount
    case ineligibleSource
    case noRecipient
    case invalidAmount
    case belowMinimum(Money)
    case exceedsPerTransaction(Money)
    case exceedsDaily(remaining: Money)
    case insufficientFunds(available: Money)
    case messageTooLong(max: Int)
    case missingSecurityQuestion
    case invalidSecurityAnswer

    public var message: String {
        switch self {
        case .noSourceAccount: "Choose an account to send from."
        case .ineligibleSource: "e-Transfers can only be sent from chequing or savings accounts."
        case .noRecipient: "Choose who to send money to."
        case .invalidAmount: "Enter an amount, like 25.00."
        case .belowMinimum(let m): "The minimum e-Transfer is \(m.formatted)."
        case .exceedsPerTransaction(let m): "The most you can send in one e-Transfer is \(m.formatted)."
        case .exceedsDaily(let r): "That is over your daily limit. You can still send \(r.formatted) today."
        case .insufficientFunds(let a): "That is more than the \(a.formatted) available in this account."
        case .messageTooLong(let n): "Messages can be at most \(n) characters."
        case .missingSecurityQuestion: "Add a security question so only the recipient can deposit this."
        case .invalidSecurityAnswer: "The answer must be 3 to 25 characters with no spaces."
        }
    }
}

/// An e-Transfer that has passed every rule. The only way to obtain one is `ETransferDraft.validate`.
public struct ETransfer: Sendable, Equatable {
    public let source: Account.ID
    public let recipient: Recipient
    public let amount: Money
    public let message: String?
    public let challenge: SecurityChallenge?

    fileprivate init(source: Account.ID, recipient: Recipient, amount: Money, message: String?, challenge: SecurityChallenge?) {
        self.source = source
        self.recipient = recipient
        self.amount = amount
        self.message = message
        self.challenge = challenge
    }
}

public struct ETransferReceipt: Sendable, Equatable {
    public let confirmationNumber: String
    public let transfer: ETransfer
    public let sentAt: Date
    public let sourceBalanceAfter: Money

    public init(confirmationNumber: String, transfer: ETransfer, sentAt: Date, sourceBalanceAfter: Money) {
        self.confirmationNumber = confirmationNumber
        self.transfer = transfer
        self.sentAt = sentAt
        self.sourceBalanceAfter = sourceBalanceAfter
    }
}

/// What the customer has typed so far. Raw text in, validated `ETransfer` (or every issue) out.
public struct ETransferDraft: Sendable, Equatable {
    public var sourceID: Account.ID?
    public var recipientID: Recipient.ID?
    public var amountText: String
    public var message: String
    public var question: String
    public var answer: String

    public init(sourceID: Account.ID? = nil, recipientID: Recipient.ID? = nil, amountText: String = "",
                message: String = "", question: String = "", answer: String = "") {
        self.sourceID = sourceID
        self.recipientID = recipientID
        self.amountText = amountText
        self.message = message
        self.question = question
        self.answer = answer
    }

    public func validate(
        accounts: [Account], recipients: [Recipient], sentToday: Money = .zero(),
        limits: ETransferLimits = .standard
    ) -> Result<ETransfer, ValidationFailure<ETransferIssue>> {
        var issues: [ETransferIssue] = []

        let source = sourceID.flatMap { id in accounts.first { $0.id == id } }
        if sourceID == nil || source == nil { issues.append(.noSourceAccount) }
        else if let source, !source.kind.canSendETransfer { issues.append(.ineligibleSource) }

        let recipient = recipientID.flatMap { id in recipients.first { $0.id == id } }
        if recipient == nil { issues.append(.noRecipient) }

        let amount = Money(string: amountText)
        if let amount, amount.isPositive {
            if amount < limits.minimum { issues.append(.belowMinimum(limits.minimum)) }
            else if amount > limits.perTransaction { issues.append(.exceedsPerTransaction(limits.perTransaction)) }
            else if sentToday + amount > limits.perDay {
                let remaining = limits.perDay - sentToday
                issues.append(.exceedsDaily(remaining: remaining.isNegative ? .zero() : remaining))
            } else if let source, source.kind.canSendETransfer, !source.canCover(amount) {
                issues.append(.insufficientFunds(available: source.availableFunds))
            }
        } else {
            issues.append(.invalidAmount)
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedMessage.count > limits.maxMessageLength { issues.append(.messageTooLong(max: limits.maxMessageLength)) }

        var challenge: SecurityChallenge?
        if let recipient, !recipient.hasAutodeposit {
            let q = question.trimmingCharacters(in: .whitespaces)
            let a = answer.trimmingCharacters(in: .whitespaces)
            if q.isEmpty { issues.append(.missingSecurityQuestion) }
            if !(3...25).contains(a.count) || a.contains(" ") { issues.append(.invalidSecurityAnswer) }
            if !q.isEmpty, (3...25).contains(a.count), !a.contains(" ") { challenge = SecurityChallenge(question: q, answer: a) }
        }

        guard issues.isEmpty, let source, let recipient, let amount else { return .failure(ValidationFailure(issues)) }
        return .success(ETransfer(source: source.id, recipient: recipient, amount: amount,
                                  message: trimmedMessage.isEmpty ? nil : trimmedMessage, challenge: challenge))
    }
}
