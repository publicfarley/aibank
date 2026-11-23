import AIBankCore
import AppIntents
import Foundation

// MARK: - Errors Siri can read

// Only errors that are CustomLocalizedStringResourceConvertible carry their message to Siri and Shortcuts.
// The core's BankError already holds customer-ready text.
extension BankError: @retroactive CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}

enum BankIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalid(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalid(let reason): "\(reason)"
        }
    }
}

// MARK: - Read-only tools

/// Tools are thin: they call the same `BankClient` and domain rules the app uses, and nothing more.
@AppIntent(.tool)
struct GetAccountsIntent {
    static let title: LocalizedStringResource = "Get Accounts"
    static let description = IntentDescription(
        "Lists all of the person's aiBank accounts with their current balances and available funds. Use it to answer how much money they have, what an account's balance is, or how much they owe on a credit card, and to look up the accounts before sending money or paying a bill. If the person isn't signed in to aiBank, it asks them to sign in first.",
        searchKeywords: ["balance", "how much money", "accounts", "net worth", "credit card balance"])
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    // Runs in the background, and only comes forward when the person needs to sign in first.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Dependency var client: BankClient
    @Dependency var store: AppStore

    // Value only: no dialog and no card. Skills call this as the first step of a payment, and a spoken
    // balance summary there reads as the final answer, so Siri stopped before the payment tool.
    func perform() async throws -> some ReturnsValue<[AccountEntity]> {
        let accounts = try await afterSigningIn(store: store, reason: "see your accounts") { [client] in
            try await client.accounts()
        }
        return .result(value: accounts.map(AccountEntity.init))
    }
}

@AppIntent(.tool)
struct GetRecentTransactionsIntent {
    static let title: LocalizedStringResource = "Get Recent Transactions"
    static let description = IntentDescription(
        "Returns the most recent transactions on one aiBank account, newest first. Use it to answer what someone spent, what was paid or received recently, or whether a payment has gone through.",
        searchKeywords: ["spending", "purchases", "activity", "statement", "history"])
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Account", description: "The account to read transactions from")
    var account: AccountEntity

    @Parameter(title: "Number of Transactions", description: "How many of the newest transactions to return, from 1 to 50", default: 10)
    var count: Int

    @Dependency var client: BankClient
    @Dependency var store: AppStore

    func perform() async throws -> some ReturnsValue<[TransactionEntity]> {
        let id = Account.ID(account.id)
        let history = TransactionHistory(try await afterSigningIn(store: store, reason: "see your transactions") { [client] in
            try await client.transactions(id)
        })
        let limit = min(max(count, 1), 50)
        return .result(value: history.transactions.prefix(limit).map(TransactionEntity.init))
    }
}

// MARK: - Money-moving tools

@AppIntent(.tool)
struct SendETransferIntent {
    static let title: LocalizedStringResource = "Send Money by Interac e-Transfer"
    static let description = IntentDescription(
        "Sends money, not a text message, by Interac e-Transfer: moves dollars from a chequing or savings account to one of the person's saved e-Transfer contacts. This takes the money out of the account right away, after the person confirms.",
        searchKeywords: ["send money", "e-transfer", "etransfer", "pay a friend", "Interac", "transfer money"])
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    // The session can end between Siri's tool calls; if it has, come forward to sign in before anything is sent.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Recipient", description: "The saved e-Transfer contact to send money to")
    var recipient: RecipientEntity

    @Parameter(title: "Amount", description: "Amount to send in Canadian dollars, such as 25.50")
    var amount: Double

    @Parameter(title: "From Account", description: "The chequing or savings account the money comes from",
               optionsProvider: ETransferSourceOptions())
    var fromAccount: AccountEntity

    @Parameter(title: "Note", description: "An optional short note that appears on the payment, up to 400 characters")
    var note: String?

    @Parameter(title: "Security Question", description: "A question only the recipient can answer. Needed only when the recipient does not have Autodeposit.")
    var securityQuestion: String?

    @Parameter(title: "Security Answer", description: "The answer to the security question: 3 to 25 characters, no spaces. Needed only when the recipient does not have Autodeposit.")
    var securityAnswer: String?

    @Dependency var client: BankClient
    @Dependency var store: AppStore

    func perform() async throws -> some ReturnsValue<ETransferReceiptEntity> & ProvidesDialog & ShowsSnippetView {
        // 1. Resolve everything the person still owes us. perform() can restart from the top when a value is
        //    requested, so nothing irreversible may happen before this block is finished.
        guard let money = Money(approximateDouble: amount) else { throw BankIntentError.invalid("That amount isn't valid.") }
        let source = Account.ID(fromAccount.id)
        // Reads only: safe to run again after a sign-in. The send itself is never retried.
        let (accounts, recipients, sourceHistory) = try await afterSigningIn(store: store, reason: "send this e-Transfer") { [client] in
            (try await client.accounts(), try await client.recipients(), try await client.transactions(source))
        }

        if recipients.first(where: { $0.id.rawValue == recipient.id })?.hasAutodeposit == false {
            guard securityQuestion?.isEmpty == false else {
                throw $securityQuestion.needsValueError("What security question should protect this transfer?")
            }
            guard securityAnswer?.isEmpty == false else {
                throw $securityAnswer.needsValueError("What is the answer to that question? Use 3 to 25 characters with no spaces.")
            }
        }

        // 2. The same pure rules the app's own form uses.
        let sentToday = TransactionHistory(sourceHistory).eTransfersSent(on: .now, calendar: .current)
        let draft = ETransferDraft(sourceID: source, recipientID: Recipient.ID(recipient.id), amountText: money.decimalString,
                                   message: note ?? "", question: securityQuestion ?? "", answer: securityAnswer ?? "")
        let transfer: ETransfer
        switch draft.validate(accounts: accounts, recipients: recipients, sentToday: sentToday) {
        case .success(let valid): transfer = valid
        case .failure(let failure): throw BankIntentError.invalid(failure.issues.map(\.message).joined(separator: " "))
        }

        // 3. Confirm immediately before the irreversible step; a "no" throws and stops here.
        try await requestConfirmation(
            actionName: .send,
            dialog: "Send \(money.formatted) to \(recipient.name) from \(fromAccount.name)?",
            snippetIntent: PaymentReviewSnippetIntent.eTransfer(transfer, fromAccountName: fromAccount.name))

        // 4. Move the money.
        let receipt = try await client.sendETransfer(transfer)
        return .result(value: ETransferReceiptEntity(receipt),
                       dialog: "Sent \(money.formatted) to \(recipient.name). Confirmation \(receipt.confirmationNumber).",
                       view: ReceiptSnippetView(receipt, fromAccountName: fromAccount.name))
    }
}

@AppIntent(.tool)
struct PayBillIntent {
    static let title: LocalizedStringResource = "Pay Bill"
    static let description = IntentDescription(
        "Pays a bill to one of the person's saved payees from a chequing or savings account. Pays today unless a later date is given, and takes the money out of the account when the payment is made, after the person confirms.",
        searchKeywords: ["pay bill", "pay my hydro", "pay phone bill", "bill payment", "schedule payment"])
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Payee", description: "The saved payee to pay, such as Phone or Toronto Hydro")
    var payee: PayeeEntity

    @Parameter(title: "Amount", description: "Amount to pay in Canadian dollars, such as 84.50")
    var amount: Double

    @Parameter(title: "From Account", description: "The chequing or savings account the money comes from",
               optionsProvider: BillPaySourceOptions())
    var fromAccount: AccountEntity

    @Parameter(title: "Pay On", description: "The day to make the payment, up to one year ahead. Leave empty to pay today.")
    var payOn: Date?

    @Dependency var client: BankClient
    @Dependency var store: AppStore

    func perform() async throws -> some ReturnsValue<BillReceiptEntity> & ProvidesDialog & ShowsSnippetView {
        guard let money = Money(approximateDouble: amount) else { throw BankIntentError.invalid("That amount isn't valid.") }
        let (accounts, payees) = try await afterSigningIn(store: store, reason: "pay this bill") { [client] in
            (try await client.accounts(), try await client.payees())
        }

        let draft = BillPaymentDraft(sourceID: Account.ID(fromAccount.id), payeeID: Payee.ID(payee.id),
                                     amountText: money.decimalString, scheduledDate: payOn)
        let payment: BillPayment
        switch draft.validate(accounts: accounts, payees: payees, now: .now, calendar: .current) {
        case .success(let valid): payment = valid
        case .failure(let failure): throw BankIntentError.invalid(failure.issues.map(\.message).joined(separator: " "))
        }

        let when = payment.isImmediate ? "today" : "on \(payment.payOn.formatted(date: .long, time: .omitted))"
        try await requestConfirmation(
            actionName: .pay,
            dialog: "Pay \(money.formatted) to \(payee.name) \(when) from \(fromAccount.name)?",
            snippetIntent: PaymentReviewSnippetIntent.bill(payment, fromAccountName: fromAccount.name))

        let receipt = try await client.payBill(payment)
        let outcome = receipt.status == .completed ? "Paid" : "Scheduled"
        return .result(value: BillReceiptEntity(receipt),
                       dialog: "\(outcome) \(money.formatted) to \(payee.name). Confirmation \(receipt.confirmationNumber).",
                       view: ReceiptSnippetView(receipt, fromAccountName: fromAccount.name))
    }
}

// MARK: - Balances answer (not a tool: the "What are my balances" phrase shows it; Siri's tools stay value-only)

struct ShowBalancesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Balances"
    static let description = IntentDescription("Says and shows the totals of the person's aiBank accounts: what they have and what they owe.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Dependency var client: BankClient
    @Dependency var store: AppStore

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let accounts = AccountsOverview(accounts: try await afterSigningIn(store: store, reason: "see your balances") { [client] in
            try await client.accounts()
        })
        let summary = "You have \(accounts.totalDeposits.formatted) in deposit accounts"
            + (accounts.totalOwed.isZero ? "." : " and owe \(accounts.totalOwed.formatted).")
        return .result(dialog: "\(summary)", snippetIntent: BalancesSnippetIntent())
    }
}

// MARK: - Navigation (not tools: they only make sense with the app on screen)

struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open aiBank Section"
    static let description = IntentDescription("Opens a section of the aiBank app: accounts, e-Transfer, bill payments or the ATM finder.")
    static var supportedModes: IntentModes { .foreground }
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$section) in aiBank") }

    @Parameter(title: "Section", description: "Which part of aiBank to open")
    var section: AppSection

    @Dependency var store: AppStore

    init() {}
    init(section: AppSection) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        store.send(.tabSelected(section.tab))
        return .result()
    }
}

struct ShowATMIntent: OpenIntent {
    static let title: LocalizedStringResource = "Show ATM"
    static let description = IntentDescription("Opens the ATM finder in aiBank with the chosen ATM selected on the map.")
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "ATM", description: "The ATM to show on the map")
    var target: ATMEntity

    @Dependency var store: AppStore

    @MainActor
    func perform() async throws -> some IntentResult {
        store.send(.tabSelected(.atms))
        store.send(.atms(.appeared(now: .now)))
        store.send(.atms(.selected(ATM.ID(target.id))))
        return .result()
    }
}

// MARK: - Zero-setup phrases

struct AIBankShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowBalancesIntent(),
            phrases: ["What are my balances in \(.applicationName)", "Show my accounts in \(.applicationName)"],
            shortTitle: "My Balances", systemImageName: "creditcard")
        AppShortcut(
            intent: OpenSectionIntent(section: .interac),
            phrases: ["Send an e-Transfer with \(.applicationName)", "Open e-Transfer in \(.applicationName)"],
            shortTitle: "Send e-Transfer", systemImageName: "paperplane")
        AppShortcut(
            intent: OpenSectionIntent(section: .bills),
            phrases: ["Pay a bill with \(.applicationName)", "Open bill payments in \(.applicationName)"],
            shortTitle: "Pay a Bill", systemImageName: "doc.text")
        AppShortcut(
            intent: OpenSectionIntent(section: .atms),
            phrases: ["Find an ATM with \(.applicationName)", "Find a cash machine in \(.applicationName)"],
            shortTitle: "Find an ATM", systemImageName: "mappin.and.ellipse")
    }
}
