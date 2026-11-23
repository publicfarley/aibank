import Foundation

/// A 16 digit card number. Parse, don't validate: once you hold one, it is well formed.
public struct CardNumber: Sendable, Equatable, Hashable {
    public let digits: String

    public init?(_ raw: String) {
        let cleaned = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == 16, cleaned.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        self.digits = cleaned
    }

    public var masked: String { "•••• •••• •••• \(digits.suffix(4))" }

    /// "4500 1234 5678 9010"
    public var spaced: String {
        stride(from: 0, to: 16, by: 4).map { i in
            let s = digits.index(digits.startIndex, offsetBy: i)
            return String(digits[s..<digits.index(s, offsetBy: 4)])
        }.joined(separator: " ")
    }

    /// Re-spaces user typing as they go, dropping anything that isn't a digit and capping at 16.
    public static func formatTyping(_ raw: String) -> String {
        let digits = String(raw.filter { ("0"..."9").contains($0) }.prefix(16))
        return stride(from: 0, to: digits.count, by: 4).map { i in
            let s = digits.index(digits.startIndex, offsetBy: i)
            let e = digits.index(s, offsetBy: min(4, digits.count - i))
            return String(digits[s..<e])
        }.joined(separator: " ")
    }
}

public struct Credentials: Sendable, Equatable {
    public let card: CardNumber
    public let password: String

    public init(card: CardNumber, password: String) {
        self.card = card
        self.password = password
    }
}

public struct Customer: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<Customer>

    public let id: ID
    public let givenName: String
    public let familyName: String
    public let email: EmailAddress
    public let memberSince: Date

    public init(id: ID, givenName: String, familyName: String, email: EmailAddress, memberSince: Date) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.memberSince = memberSince
    }

    public var fullName: String { "\(givenName) \(familyName)" }
    public var initials: String { "\(givenName.prefix(1))\(familyName.prefix(1))".uppercased() }
}

public struct Session: Sendable, Equatable {
    public let customer: Customer
    public let expiresAt: Date

    public init(customer: Customer, expiresAt: Date) {
        self.customer = customer
        self.expiresAt = expiresAt
    }
}

/// Problems with the sign-in form, found before anything is sent to the server.
public enum SignInIssue: Error, Sendable, Equatable {
    case cardNumberIncomplete
    case passwordTooShort

    public var message: String {
        switch self {
        case .cardNumberIncomplete: "Enter your 16 digit card number."
        case .passwordTooShort: "Your password must be at least 6 characters."
        }
    }
}

public enum SignInRules {
    public static let minimumPasswordLength = 6
    public static let maxFailedAttempts = 3
    public static let lockoutDuration: TimeInterval = 5 * 60
    /// A session ends after this long without activity: no requests to the bank, or the app left in the background.
    public static let idleTimeout: TimeInterval = 30 * 60

    public static func credentials(cardText: String, password: String) -> Result<Credentials, SignInIssue> {
        guard let card = CardNumber(cardText) else { return .failure(.cardNumberIncomplete) }
        guard password.count >= minimumPasswordLength else { return .failure(.passwordTooShort) }
        return .success(Credentials(card: card, password: password))
    }
}
