import AIBankCore
import Foundation

public enum FakeBackend {
    /// Demo credentials, for display on the sign-in screen.
    public static let demoCardNumber = SeedData.demoCard
    public static let demoPassword = SeedData.demoPassword

    /// A `BankClient` backed by an in-process fake server that speaks JSON and persists its state.
    /// - Parameter latency: simulated network delay per request.
    public static func client(
        now: @escaping @Sendable () -> Date = { Date() },
        persistence: Persistence = .none,
        latency: Duration = .milliseconds(350)
    ) -> BankClient {
        let server = FakeBankServer(now: now, persistence: persistence, latency: latency)
        let api = API(server: server)

        return BankClient(
            signIn: { credentials in
                try Session(dto: try await api.post(.signIn, CredentialsDTO(credentials), as: SessionDTO.self))
            },
            signOut: { _ = try await api.post(.signOut, Empty(), as: Empty.self) },
            accounts: {
                try await api.get(.accounts, as: [AccountDTO].self).map(Account.init(dto:))
            },
            transactions: { id in
                try await api.get(.transactions(accountId: id.rawValue), as: [TransactionDTO].self).map(Transaction.init(dto:))
            },
            recipients: {
                try await api.get(.recipients, as: [RecipientDTO].self).map(Recipient.init(dto:))
            },
            payees: {
                try await api.get(.payees, as: [PayeeDTO].self).map(Payee.init(dto:))
            },
            atms: {
                try await api.get(.atms, as: [ATMDTO].self).map(ATM.init(dto:))
            },
            sendETransfer: { transfer in
                let dto = try await api.post(.sendETransfer, ETransferRequestDTO(transfer), as: ETransferReceiptDTO.self)
                return ETransferReceipt(
                    confirmationNumber: dto.confirmationNumber, transfer: transfer,
                    sentAt: try Wire.date(dto.sentAt, field: "sentAt"),
                    sourceBalanceAfter: try Wire.money(dto.balanceAfter, transfer.amount.currency.rawValue, field: "balanceAfter"))
            },
            payBill: { payment in
                let dto = try await api.post(.payBill, BillPaymentRequestDTO(payment), as: BillPaymentReceiptDTO.self)
                return BillPaymentReceipt(
                    confirmationNumber: dto.confirmationNumber,
                    payment: payment,
                    status: dto.status == "scheduled" ? .scheduled : .completed,
                    processedAt: try Wire.date(dto.processedAt, field: "processedAt"),
                    sourceBalanceAfter: try Wire.money(dto.balanceAfter, payment.amount.currency.rawValue, field: "balanceAfter"))
            })
    }
}

private struct Empty: Codable {}

/// The fake network layer: JSON in, JSON out, errors mapped to `BankError` at the edge.
private struct API: Sendable {
    let server: FakeBankServer

    func get<T: Decodable>(_ endpoint: Endpoint, as: T.Type) async throws -> T {
        try decode(await server.handle(endpoint, body: nil))
    }

    func post<B: Encodable, T: Decodable>(_ endpoint: Endpoint, _ body: B, as: T.Type) async throws -> T {
        try decode(await server.handle(endpoint, body: try JSONEncoder().encode(body)))
    }

    private func decode<T: Decodable>(_ response: Response) throws -> T {
        guard (200..<300).contains(response.status) else { throw Self.error(from: response) }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw BankError.malformedResponse(String(describing: error)) }
    }

    private static func error(from response: Response) -> BankError {
        guard let dto = try? JSONDecoder().decode(ErrorDTO.self, from: response.body) else {
            return .malformedResponse("status \(response.status)")
        }
        switch dto.code {
        case "invalid_credentials": return .invalidCredentials
        case "not_signed_in": return .notSignedIn
        case "session_expired": return .sessionExpired
        case "insufficient_funds": return .insufficientFunds
        case "not_found": return .notFound(dto.message)
        case "limit_exceeded": return .limitExceeded(dto.message)
        default: return .rejected(dto.message)
        }
    }
}
