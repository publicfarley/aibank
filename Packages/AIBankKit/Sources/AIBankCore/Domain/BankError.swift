import Foundation

/// Every way a banking operation can fail, as a value. Messages are written for the customer.
public enum BankError: Error, Equatable, Sendable {
    case invalidCredentials
    case accountLocked
    case notSignedIn
    case sessionExpired
    case offline
    case notFound(String)
    case insufficientFunds
    case limitExceeded(String)
    case rejected(String)
    case malformedResponse(String)

    public var message: String {
        switch self {
        case .invalidCredentials: "That card number or password isn't right. Please try again."
        case .accountLocked: "Too many failed attempts. Please wait a few minutes before trying again."
        case .notSignedIn: "Please sign in to aiBank first."
        case .sessionExpired: "Your session has expired. Please sign in again."
        case .offline: "aiBank can't be reached right now. Check your connection and try again."
        case .notFound(let what): "We couldn't find \(what)."
        case .insufficientFunds: "There aren't enough available funds in that account."
        case .limitExceeded(let detail): detail
        case .rejected(let detail): detail
        case .malformedResponse: "Something went wrong on our side. Please try again later."
        }
    }
}
