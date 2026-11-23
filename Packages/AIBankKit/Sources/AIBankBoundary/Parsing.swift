import AIBankCore
import Foundation

/// Where untrusted wire data becomes trusted domain data. Anything malformed stops here.
enum BoundaryError: Error, Equatable {
    case malformed(field: String, value: String)
}

enum Wire {
    static func date(_ text: String, field: String) throws -> Date {
        guard let d = ISO8601DateFormatter().date(from: text) else { throw BoundaryError.malformed(field: field, value: text) }
        return d
    }

    static func string(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    static func money(_ text: String, _ currency: String, field: String) throws -> Money {
        guard let c = Currency(rawValue: currency), let m = Money(string: text, currency: c) else {
            throw BoundaryError.malformed(field: field, value: "\(text) \(currency)")
        }
        return m
    }

    static func require<T>(_ value: T?, field: String, _ raw: String) throws -> T {
        guard let value else { throw BoundaryError.malformed(field: field, value: raw) }
        return value
    }
}

// MARK: DTO -> domain

extension Customer {
    init(dto: CustomerDTO) throws {
        self.init(
            id: Customer.ID(dto.id), givenName: dto.givenName, familyName: dto.familyName,
            email: try Wire.require(EmailAddress(dto.email), field: "email", dto.email),
            memberSince: try Wire.date(dto.memberSince, field: "memberSince"))
    }
}

extension Session {
    init(dto: SessionDTO) throws {
        self.init(customer: try Customer(dto: dto.customer), expiresAt: try Wire.date(dto.expiresAt, field: "expiresAt"))
    }
}

extension Account {
    init(dto: AccountDTO) throws {
        self.init(
            id: Account.ID(dto.id),
            kind: try Wire.require(AccountKind(rawValue: dto.kind), field: "kind", dto.kind),
            nickname: dto.nickname,
            number: try Wire.require(AccountNumber(dto.number), field: "number", "•••"),
            balance: try Wire.money(dto.balance, dto.currency, field: "balance"),
            borrowingLimit: try Wire.money(dto.borrowingLimit, dto.currency, field: "borrowingLimit"),
            interestRateBasisPoints: dto.interestRateBasisPoints)
    }
}

extension Transaction {
    init(dto: TransactionDTO) throws {
        self.init(
            id: Transaction.ID(dto.id), accountID: Account.ID(dto.accountId),
            kind: try Wire.require(TransactionKind(rawValue: dto.kind), field: "kind", dto.kind),
            amount: try Wire.money(dto.amount, dto.currency, field: "amount"),
            date: try Wire.date(dto.date, field: "date"),
            status: dto.status == "pending" ? .pending : .posted,
            title: dto.title, detail: dto.detail,
            category: TransactionCategory(rawValue: dto.category) ?? .other)
    }
}

extension Recipient {
    init(dto: RecipientDTO) throws {
        self.init(id: Recipient.ID(dto.id), name: dto.name,
                  email: try Wire.require(EmailAddress(dto.email), field: "email", dto.email),
                  hasAutodeposit: dto.autodeposit)
    }
}

extension Biller {
    init(dto: BillerDTO) throws {
        guard dto.minAccountLength <= dto.maxAccountLength else {
            throw BoundaryError.malformed(field: "accountLength", value: "\(dto.minAccountLength)...\(dto.maxAccountLength)")
        }
        self.init(id: Biller.ID(dto.id), name: dto.name,
                  category: BillerCategory(rawValue: dto.category) ?? .other,
                  accountNumberLength: dto.minAccountLength...dto.maxAccountLength)
    }
}

extension Payee {
    init(dto: PayeeDTO) throws {
        self.init(id: Payee.ID(dto.id), biller: try Biller(dto: dto.biller), accountNumber: dto.accountNumber,
                  nickname: dto.nickname,
                  lastPayment: try dto.lastPayment.map { try Wire.money($0, "CAD", field: "lastPayment") })
    }
}

extension ATM {
    init(dto: ATMDTO) throws {
        var services: ATMServices = []
        for s in dto.services {
            switch s {
            case "withdrawal": services.insert(.cashWithdrawal)
            case "deposit": services.insert(.deposit)
            case "accessible": services.insert(.wheelchairAccessible)
            case "24h": services.insert(.open24Hours)
            case "drivethrough": services.insert(.driveThrough)
            default: throw BoundaryError.malformed(field: "services", value: s)
            }
        }
        self.init(
            id: ATM.ID(dto.id), name: dto.name,
            network: try Wire.require(ATMNetwork(rawValue: dto.network), field: "network", dto.network),
            address: dto.address, city: dto.city,
            coordinate: Coordinate(latitude: dto.latitude, longitude: dto.longitude),
            services: services,
            hours: DailyHours(opensAtMinute: dto.opensAtMinute, closesAtMinute: dto.closesAtMinute))
    }
}

// MARK: domain -> DTO

extension CredentialsDTO {
    init(_ credentials: Credentials) { self.init(cardNumber: credentials.card.digits, password: credentials.password) }
}

extension ETransferRequestDTO {
    init(_ t: ETransfer) {
        self.init(accountId: t.source.rawValue, recipientId: t.recipient.id.rawValue, amount: t.amount.decimalString,
                  message: t.message, question: t.challenge?.question, answer: t.challenge?.answer)
    }
}

extension BillPaymentRequestDTO {
    init(_ p: BillPayment) {
        self.init(accountId: p.source.rawValue, payeeId: p.payee.id.rawValue, amount: p.amount.decimalString,
                  payOn: Wire.string(p.payOn))
    }
}
