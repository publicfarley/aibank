import AIBankCore
import AppIntents
import Foundation

// Entities are the shell's view of the domain for Siri, Shortcuts and Spotlight. They are built *from* domain values
// and never the other way round: all rules stay in the core.
//
// Privacy decisions:
//  - Entities are findable through EnumerableEntityQuery (runs inside the app, only when the person names aiBank),
//    not indexed in Spotlight, because account and payee names are sensitive.
//  - Full account numbers and email addresses never become entity properties; last-4 is `.internal`.

// MARK: - Enums

enum AccountKindEnum: String, AppEnum {
    case chequing, savings, tfsa, creditCard, lineOfCredit

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account Type"
    static let caseDisplayRepresentations: [AccountKindEnum: DisplayRepresentation] = [
        .chequing: "Chequing",
        .savings: "Savings",
        .tfsa: "TFSA",
        .creditCard: "Credit Card",
        .lineOfCredit: "Line of Credit",
    ]

    init(_ kind: AccountKind) { self = AccountKindEnum(rawValue: kind.rawValue) ?? .chequing }
}

enum AppSection: String, AppEnum {
    case accounts, interac, bills, atms

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "aiBank Section"
    static let caseDisplayRepresentations: [AppSection: DisplayRepresentation] = [
        .accounts: "Accounts",
        .interac: "Interac e-Transfer",
        .bills: "Pay Bills",
        .atms: "ATM Finder",
    ]

    var tab: AppTab { AppTab(rawValue: rawValue) ?? .accounts }
}

// MARK: - Account

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    var id: String

    @Property(title: "Name", description: "The account's nickname, such as Everyday Chequing")
    var name: String

    @Property(title: "Account Type", description: "Whether this is chequing, savings, a TFSA, a credit card or a line of credit")
    var kind: AccountKindEnum

    @Property(title: "Balance", description: "Current balance in Canadian dollars. Negative means money owed on a credit card or line of credit.")
    var balance: Double

    @Property(title: "Available Funds", description: "Dollars that can be spent right now, including overdraft or credit room")
    var availableFunds: Double

    @Property(title: "Ending Digits", description: "Last four digits of the account number", visibility: .internal)
    var last4: String

    var kindTitle: String

    init(_ account: Account) {
        self.id = account.id.rawValue
        self.kindTitle = account.kind.title
        self.name = account.displayName
        self.kind = AccountKindEnum(account.kind)
        self.balance = account.balance.approximateDouble
        self.availableFunds = account.availableFunds.approximateDouble
        self.last4 = account.number.last4
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kindTitle)", image: .init(systemName: AccountKind(rawValue: kind.rawValue)?.symbolName ?? "banknote"))
    }
}

struct AccountQuery: EnumerableEntityQuery {
    @Dependency var client: BankClient

    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    func allEntities() async throws -> [AccountEntity] {
        try await client.accounts().map(AccountEntity.init)
    }
}

/// Pickers for a tool's "From Account": only accounts the core allows as a source, so Shortcuts and Siri never
/// offer a TFSA or credit product that validation would reject afterwards.
struct ETransferSourceOptions: DynamicOptionsProvider {
    @Dependency var client: BankClient

    func results() async throws -> [AccountEntity] {
        AccountsOverview(accounts: try await client.accounts()).eTransferSources.map(AccountEntity.init)
    }
}

struct BillPaySourceOptions: DynamicOptionsProvider {
    @Dependency var client: BankClient

    func results() async throws -> [AccountEntity] {
        AccountsOverview(accounts: try await client.accounts()).billPaySources.map(AccountEntity.init)
    }
}

// MARK: - Recipient

struct RecipientEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "e-Transfer Contact"
    static let defaultQuery = RecipientQuery()

    var id: String

    @Property(title: "Name", description: "The contact's full name, such as Sam Patel")
    var name: String

    @Property(title: "Has Autodeposit", description: "True when money sent to this contact is deposited automatically, so no security question is needed")
    var hasAutodeposit: Bool

    @Property(title: "Email", description: "The contact's e-Transfer email address", visibility: .internal)
    var email: String

    init(_ recipient: Recipient) {
        self.id = recipient.id.rawValue
        self.name = recipient.name
        self.hasAutodeposit = recipient.hasAutodeposit
        self.email = recipient.email.value
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: hasAutodeposit ? "Autodeposit" : "Security question required")
    }
}

struct RecipientQuery: EnumerableEntityQuery {
    @Dependency var client: BankClient

    func entities(for identifiers: [String]) async throws -> [RecipientEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    func allEntities() async throws -> [RecipientEntity] {
        try await client.recipients().map(RecipientEntity.init)
    }
}

// MARK: - Payee

struct PayeeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bill Payee"
    static let defaultQuery = PayeeQuery()

    var id: String

    @Property(title: "Name", description: "What the person calls this payee, such as Phone or Toronto Hydro")
    var name: String

    @Property(title: "Company", description: "The company that is paid, such as Maple Mobile")
    var company: String

    @Property(title: "Category", description: "The kind of bill, such as utilities, telecom, insurance or taxes")
    var category: String

    @Property(title: "Last Payment", description: "Amount of the most recent payment in Canadian dollars, if there has been one")
    var lastPayment: Double?

    @Property(title: "Account Number", description: "The person's account number with this company", visibility: .internal)
    var accountNumber: String

    init(_ payee: Payee) {
        self.id = payee.id.rawValue
        self.name = payee.displayName
        self.company = payee.biller.name
        self.category = payee.biller.category.title
        self.lastPayment = payee.lastPayment?.approximateDouble
        self.accountNumber = payee.accountNumber
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(company)")
    }
}

struct PayeeQuery: EnumerableEntityQuery {
    @Dependency var client: BankClient

    func entities(for identifiers: [String]) async throws -> [PayeeEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    func allEntities() async throws -> [PayeeEntity] {
        try await client.payees().map(PayeeEntity.init)
    }
}

// MARK: - ATM

struct ATMEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "ATM"
    static let defaultQuery = ATMQuery()

    var id: String

    @Property(title: "Name", description: "The ATM's location name, such as Union Station Concourse")
    var name: String

    @Property(title: "Address", description: "Street address in Toronto")
    var address: String

    @Property(title: "Network", description: "aiBank for the bank's own machines, or Partner network, which charges a withdrawal fee")
    var network: String

    @Property(title: "Hours", description: "Opening hours every day, or Open 24 hours")
    var hours: String

    @Property(title: "Takes Deposits", description: "Whether cash and cheque deposits are accepted")
    var takesDeposits: Bool

    init(_ atm: ATM) {
        self.id = atm.id.rawValue
        self.name = atm.name
        self.address = "\(atm.address), \(atm.city)"
        self.network = atm.network.title
        self.hours = atm.hoursText
        self.takesDeposits = atm.services.contains(.deposit)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(address)")
    }
}

struct ATMQuery: EnumerableEntityQuery {
    @Dependency var client: BankClient

    func entities(for identifiers: [String]) async throws -> [ATMEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    func allEntities() async throws -> [ATMEntity] {
        try await client.atms().map(ATMEntity.init)
    }
}

// MARK: - Values returned from tools (not stored, never looked up)

struct TransactionEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction"

    @Property(title: "Description", description: "Who was paid or who paid, such as Greenfield Market")
    var title: String

    @Property(title: "Amount", description: "Dollars in Canadian currency. Negative means money left the account, positive means money came in.")
    var amount: Double

    @Property(title: "Date", description: "When the transaction happened")
    var date: Date

    @Property(title: "Category", description: "Spending category, such as Groceries, Dining or Transport")
    var category: String

    @Property(title: "Pending", description: "True if the transaction hasn't finished posting to the account yet")
    var isPending: Bool

    init() {}

    init(_ t: Transaction) {
        self.title = t.title
        self.amount = t.amount.approximateDouble
        self.date = t.date
        self.category = t.category.title
        self.isPending = t.status == .pending
    }

    var displayRepresentation: DisplayRepresentation {
        let money = Money(approximateDouble: amount)?.formatted ?? "\(amount)"
        return DisplayRepresentation(title: "\(title)", subtitle: "\(money)")
    }
}

struct ETransferReceiptEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "e-Transfer Receipt"

    @Property(title: "Confirmation Number", description: "The bank's reference for this e-Transfer, such as CA100123")
    var confirmationNumber: String

    @Property(title: "Recipient", description: "Name of the contact who was sent money")
    var recipient: String

    @Property(title: "Amount", description: "Dollars sent, in Canadian currency")
    var amount: Double

    @Property(title: "Balance After", description: "Balance of the source account after sending, in Canadian dollars")
    var balanceAfter: Double

    init() {}

    init(_ r: ETransferReceipt) {
        self.confirmationNumber = r.confirmationNumber
        self.recipient = r.transfer.recipient.name
        self.amount = r.transfer.amount.approximateDouble
        self.balanceAfter = r.sourceBalanceAfter.approximateDouble
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(confirmationNumber)", subtitle: "\(Money(approximateDouble: amount)?.formatted ?? "") to \(recipient)")
    }
}

struct BillReceiptEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bill Payment Receipt"

    @Property(title: "Confirmation Number", description: "The bank's reference for this payment, such as CA100124")
    var confirmationNumber: String

    @Property(title: "Payee", description: "Who was paid")
    var payee: String

    @Property(title: "Amount", description: "Dollars paid, in Canadian currency")
    var amount: Double

    @Property(title: "Status", description: "Completed if paid now, or Scheduled if it will be paid on a later date")
    var status: String

    @Property(title: "Pay Date", description: "The day the payment is made or was made")
    var payDate: Date

    init() {}

    init(_ r: BillPaymentReceipt) {
        self.confirmationNumber = r.confirmationNumber
        self.payee = r.payment.payee.displayName
        self.amount = r.payment.amount.approximateDouble
        self.status = r.status == .completed ? "Completed" : "Scheduled"
        self.payDate = r.payment.payOn
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(confirmationNumber)", subtitle: "\(Money(approximateDouble: amount)?.formatted ?? "") to \(payee)")
    }
}
