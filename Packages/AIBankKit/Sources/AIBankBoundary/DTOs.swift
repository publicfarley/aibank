import Foundation

// Wire formats. These are the only Codable types in the project: domain types are never decoded directly.
// Money travels as decimal strings ("1234.50"), dates as ISO-8601 strings.

struct CredentialsDTO: Codable, Equatable {
    var cardNumber: String
    var password: String
}

struct CustomerDTO: Codable, Equatable {
    var id: String
    var givenName: String
    var familyName: String
    var email: String
    var memberSince: String
}

struct SessionDTO: Codable, Equatable {
    var customer: CustomerDTO
    var expiresAt: String
}

struct AccountDTO: Codable, Equatable {
    var id: String
    var kind: String
    var nickname: String
    var number: String
    var currency: String
    var balance: String
    var borrowingLimit: String
    var interestRateBasisPoints: Int
}

struct TransactionDTO: Codable, Equatable {
    var id: String
    var accountId: String
    var kind: String
    var amount: String
    var currency: String
    var date: String
    var status: String
    var title: String
    var detail: String?
    var category: String
}

struct RecipientDTO: Codable, Equatable {
    var id: String
    var name: String
    var email: String
    var autodeposit: Bool
}

struct BillerDTO: Codable, Equatable {
    var id: String
    var name: String
    var category: String
    var minAccountLength: Int
    var maxAccountLength: Int
}

struct PayeeDTO: Codable, Equatable {
    var id: String
    var biller: BillerDTO
    var accountNumber: String
    var nickname: String?
    var lastPayment: String?
}

struct ATMDTO: Codable, Equatable {
    var id: String
    var name: String
    var network: String
    var address: String
    var city: String
    var latitude: Double
    var longitude: Double
    var services: [String]
    var opensAtMinute: Int
    var closesAtMinute: Int
}

struct ETransferRequestDTO: Codable, Equatable {
    var accountId: String
    var recipientId: String
    var amount: String
    var message: String?
    var question: String?
    var answer: String?
}

struct ETransferReceiptDTO: Codable, Equatable {
    var confirmationNumber: String
    var sentAt: String
    var balanceAfter: String
}

struct BillPaymentRequestDTO: Codable, Equatable {
    var accountId: String
    var payeeId: String
    var amount: String
    var payOn: String
}

struct BillPaymentReceiptDTO: Codable, Equatable {
    var confirmationNumber: String
    var status: String
    var processedAt: String
    var balanceAfter: String
}

struct ErrorDTO: Codable, Equatable {
    var code: String
    var message: String
}
