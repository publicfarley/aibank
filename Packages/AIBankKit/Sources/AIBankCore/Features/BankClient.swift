import Foundation

/// Everything the app asks of "the bank". The core only knows this shape; the boundary module provides
/// a live implementation that talks to the (fake) server, and tests provide literal stubs.
public struct BankClient: Sendable {
    public var signIn: @Sendable (Credentials) async throws -> Session
    public var signOut: @Sendable () async throws -> Void
    public var accounts: @Sendable () async throws -> [Account]
    public var transactions: @Sendable (Account.ID) async throws -> [Transaction]
    public var recipients: @Sendable () async throws -> [Recipient]
    public var payees: @Sendable () async throws -> [Payee]
    public var atms: @Sendable () async throws -> [ATM]
    public var sendETransfer: @Sendable (ETransfer) async throws -> ETransferReceipt
    public var payBill: @Sendable (BillPayment) async throws -> BillPaymentReceipt

    public init(
        signIn: @escaping @Sendable (Credentials) async throws -> Session,
        signOut: @escaping @Sendable () async throws -> Void,
        accounts: @escaping @Sendable () async throws -> [Account],
        transactions: @escaping @Sendable (Account.ID) async throws -> [Transaction],
        recipients: @escaping @Sendable () async throws -> [Recipient],
        payees: @escaping @Sendable () async throws -> [Payee],
        atms: @escaping @Sendable () async throws -> [ATM],
        sendETransfer: @escaping @Sendable (ETransfer) async throws -> ETransferReceipt,
        payBill: @escaping @Sendable (BillPayment) async throws -> BillPaymentReceipt
    ) {
        self.signIn = signIn
        self.signOut = signOut
        self.accounts = accounts
        self.transactions = transactions
        self.recipients = recipients
        self.payees = payees
        self.atms = atms
        self.sendETransfer = sendETransfer
        self.payBill = payBill
    }
}

/// All nondeterminism the shell injects into effects.
public struct BankEnvironment: Sendable {
    public var client: BankClient
    public var now: @Sendable () -> Date

    public init(client: BankClient, now: @escaping @Sendable () -> Date) {
        self.client = client
        self.now = now
    }
}

extension BankError {
    /// Anything a client throws becomes a `BankError` before it reaches a reducer.
    public static func wrap(_ error: any Error) -> BankError {
        (error as? BankError) ?? .offline
    }
}
