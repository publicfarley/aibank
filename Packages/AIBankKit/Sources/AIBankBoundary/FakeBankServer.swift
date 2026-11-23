import AIBankCore
import Foundation

struct ServerStore: Codable, Equatable {
    var customer: CustomerDTO
    var accounts: [AccountDTO]
    var transactions: [TransactionDTO]
    var recipients: [RecipientDTO]
    var payees: [PayeeDTO]
    var atms: [ATMDTO]
    var session: SessionDTO?
    var confirmationCounter: Int
}

/// Where the fake server keeps its state between launches. Intents run while the app may be off screen, so
/// state changed by Siri must survive the process exiting.
public struct Persistence: Sendable {
    public var load: @Sendable () -> Data?
    public var save: @Sendable (Data) -> Void

    public init(load: @escaping @Sendable () -> Data?, save: @escaping @Sendable (Data) -> Void) {
        self.load = load
        self.save = save
    }

    public static let none = Persistence(load: { nil }, save: { _ in })

    public static func file(_ url: URL) -> Persistence {
        Persistence(
            load: { try? Data(contentsOf: url) },
            save: { data in
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            })
    }
}

enum Endpoint: Sendable, Equatable {
    case signIn, signOut
    case accounts, transactions(accountId: String)
    case recipients, payees, atms
    case sendETransfer, payBill
}

struct Response: Sendable {
    var status: Int
    var body: Data
}

struct ServerFailure: Error {
    var status: Int
    var code: String
    var message: String
}

/// A stand-in for a bank's backend. It speaks JSON over a fake transport, enforces its own rules, simulates
/// latency, and persists its state. Nothing leaves the device.
actor FakeBankServer {
    private var store: ServerStore
    private let persistence: Persistence
    private let now: @Sendable () -> Date
    private let latency: Duration
    /// Sliding expiry: each authenticated request pushes the session's end out again.
    private let idleTimeout = SignInRules.idleTimeout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(now: @escaping @Sendable () -> Date, persistence: Persistence, latency: Duration) {
        self.now = now
        self.persistence = persistence
        self.latency = latency
        if let data = persistence.load(), let saved = try? JSONDecoder().decode(ServerStore.self, from: data) {
            self.store = saved
        } else {
            self.store = SeedData.make(now: now())
            if let data = try? JSONEncoder().encode(store) { persistence.save(data) }
        }
    }

    func handle(_ endpoint: Endpoint, body: Data?) async -> Response {
        if latency > .zero { try? await Task.sleep(for: latency) }
        do {
            let data = try route(endpoint, body: body)
            return Response(status: 200, body: data)
        } catch let failure as ServerFailure {
            let dto = ErrorDTO(code: failure.code, message: failure.message)
            return Response(status: failure.status, body: (try? encoder.encode(dto)) ?? Data())
        } catch {
            let dto = ErrorDTO(code: "bad_request", message: "The request could not be understood.")
            return Response(status: 400, body: (try? encoder.encode(dto)) ?? Data())
        }
    }

    // MARK: Routing

    private func route(_ endpoint: Endpoint, body: Data?) throws -> Data {
        switch endpoint {
        case .signIn:
            let creds = try decode(CredentialsDTO.self, body)
            guard creds.cardNumber == SeedData.demoCard, creds.password == SeedData.demoPassword else {
                throw ServerFailure(status: 401, code: "invalid_credentials", message: "Invalid credentials")
            }
            let session = SessionDTO(customer: store.customer, expiresAt: Wire.string(now().addingTimeInterval(idleTimeout)))
            store.session = session
            commit()
            return try encoder.encode(session)

        case .signOut:
            store.session = nil
            commit()
            return Data("{}".utf8)

        case .accounts:
            _ = try requireSession()
            return try encoder.encode(store.accounts)

        case .transactions(let accountId):
            _ = try requireSession()
            guard store.accounts.contains(where: { $0.id == accountId }) else {
                throw ServerFailure(status: 404, code: "not_found", message: "account")
            }
            return try encoder.encode(store.transactions.filter { $0.accountId == accountId })

        case .recipients:
            _ = try requireSession()
            return try encoder.encode(store.recipients)

        case .payees:
            _ = try requireSession()
            return try encoder.encode(store.payees)

        case .atms:
            _ = try requireSession()
            return try encoder.encode(store.atms)

        case .sendETransfer:
            _ = try requireSession()
            return try encoder.encode(try sendETransfer(try decode(ETransferRequestDTO.self, body)))

        case .payBill:
            _ = try requireSession()
            return try encoder.encode(try payBill(try decode(BillPaymentRequestDTO.self, body)))
        }
    }

    // MARK: Business rules (the server never trusts the client)

    private func sendETransfer(_ req: ETransferRequestDTO) throws -> ETransferReceiptDTO {
        guard let index = store.accounts.firstIndex(where: { $0.id == req.accountId }) else {
            throw ServerFailure(status: 404, code: "not_found", message: "the account to send from")
        }
        guard let recipient = store.recipients.first(where: { $0.id == req.recipientId }) else {
            throw ServerFailure(status: 404, code: "not_found", message: "that recipient")
        }
        let account = store.accounts[index]
        guard account.kind == "chequing" || account.kind == "savings" else {
            throw ServerFailure(status: 422, code: "rejected", message: "e-Transfers can only be sent from chequing or savings accounts.")
        }
        guard let amount = Money(string: req.amount), amount.isPositive else {
            throw ServerFailure(status: 422, code: "rejected", message: "That amount isn't valid.")
        }
        if amount > .cad(300_000) {
            throw ServerFailure(status: 422, code: "limit_exceeded", message: "The most you can send in one e-Transfer is $3,000.00.")
        }
        let calendar = Calendar.current
        let sentToday = store.transactions
            .filter { $0.kind == "eTransferSent" && (try? Wire.date($0.date, field: "date")).map { calendar.isDate($0, inSameDayAs: now()) } == true }
            .compactMap { Money(string: $0.amount)?.magnitude }
            .reduce(Money.zero()) { $0 + $1 }
        if sentToday + amount > .cad(1_000_000) {
            throw ServerFailure(status: 422, code: "limit_exceeded", message: "That is over your daily e-Transfer limit of $10,000.00.")
        }
        guard let balance = Money(string: account.balance), let limit = Money(string: account.borrowingLimit),
              amount <= balance + limit else {
            throw ServerFailure(status: 422, code: "insufficient_funds", message: "Insufficient funds")
        }
        if !recipient.autodeposit, (req.question ?? "").isEmpty || (req.answer ?? "").isEmpty {
            throw ServerFailure(status: 422, code: "rejected", message: "A security question and answer are required for this recipient.")
        }

        let newBalance = balance - amount
        store.accounts[index].balance = newBalance.decimalString
        let confirmation = nextConfirmation()
        store.transactions.append(TransactionDTO(
            id: "txn-\(confirmation)", accountId: account.id, kind: "eTransferSent", amount: (-amount).decimalString,
            currency: account.currency, date: Wire.string(now()), status: "posted",
            title: "e-Transfer to \(recipient.name)", detail: req.message, category: "transfers"))
        commit()
        return ETransferReceiptDTO(confirmationNumber: confirmation, sentAt: Wire.string(now()), balanceAfter: newBalance.decimalString)
    }

    private func payBill(_ req: BillPaymentRequestDTO) throws -> BillPaymentReceiptDTO {
        guard let index = store.accounts.firstIndex(where: { $0.id == req.accountId }) else {
            throw ServerFailure(status: 404, code: "not_found", message: "the account to pay from")
        }
        guard let payeeIndex = store.payees.firstIndex(where: { $0.id == req.payeeId }) else {
            throw ServerFailure(status: 404, code: "not_found", message: "that payee")
        }
        let account = store.accounts[index]
        guard account.kind == "chequing" || account.kind == "savings" else {
            throw ServerFailure(status: 422, code: "rejected", message: "Bills can only be paid from chequing or savings accounts.")
        }
        guard let amount = Money(string: req.amount), amount.isPositive else {
            throw ServerFailure(status: 422, code: "rejected", message: "That amount isn't valid.")
        }
        guard let balance = Money(string: account.balance), let limit = Money(string: account.borrowingLimit),
              amount <= balance + limit else {
            throw ServerFailure(status: 422, code: "insufficient_funds", message: "Insufficient funds")
        }
        let payOn = try Wire.date(req.payOn, field: "payOn")
        let immediate = Calendar.current.isDate(payOn, inSameDayAs: now()) || payOn < now()
        let confirmation = nextConfirmation()
        var newBalance = balance

        if immediate {
            newBalance = balance - amount
            store.accounts[index].balance = newBalance.decimalString
            let payee = store.payees[payeeIndex]
            store.transactions.append(TransactionDTO(
                id: "txn-\(confirmation)", accountId: account.id, kind: "billPayment", amount: (-amount).decimalString,
                currency: account.currency, date: Wire.string(now()), status: "posted",
                title: payee.biller.name, detail: "Bill payment", category: payee.biller.category == "housing" ? "housing" : "utilities"))
        }
        store.payees[payeeIndex].lastPayment = amount.decimalString
        commit()
        return BillPaymentReceiptDTO(confirmationNumber: confirmation, status: immediate ? "completed" : "scheduled",
                                     processedAt: Wire.string(now()), balanceAfter: newBalance.decimalString)
    }

    // MARK: Helpers

    @discardableResult
    private func requireSession() throws -> SessionDTO {
        guard let session = store.session else {
            throw ServerFailure(status: 401, code: "not_signed_in", message: "Not signed in")
        }
        guard let expires = try? Wire.date(session.expiresAt, field: "expiresAt"), expires > now() else {
            store.session = nil
            commit()
            throw ServerFailure(status: 401, code: "session_expired", message: "Session expired")
        }
        var renewed = session
        renewed.expiresAt = Wire.string(now().addingTimeInterval(idleTimeout))
        store.session = renewed
        commit()
        return renewed
    }

    private func nextConfirmation() -> String {
        store.confirmationCounter += 1
        return "CA\(store.confirmationCounter)"
    }

    private func decode<T: Decodable>(_ type: T.Type, _ body: Data?) throws -> T {
        guard let body else { throw ServerFailure(status: 400, code: "bad_request", message: "Missing body") }
        return try decoder.decode(type, from: body)
    }

    private func commit() {
        if let data = try? encoder.encode(store) { persistence.save(data) }
    }
}
