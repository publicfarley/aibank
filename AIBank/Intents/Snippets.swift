import AIBankCore
import AppIntents
import SwiftUI

// Cards Siri shows alongside a tool's spoken answer.
//
//  - Balances is a live SnippetIntent: the system may re-run its perform() to redraw (state restoration, after a
//    button tap), so it re-reads the accounts every time and never changes anything.
//  - Receipts are static result(view:) snapshots: a confirmation never changes, so there is nothing to re-run.
//
// Views take domain values only; formatting rules (Money.formatted, AccountsOverview totals) come from the core.

// MARK: - Balances

struct BalancesSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Account Balances"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Dependency var client: BankClient

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let overview = AccountsOverview(accounts: try await client.accounts())   // read only
        return .result(view: BalancesSnippetView(overview: overview))
    }
}

struct BalancesSnippetView: View {
    let overview: AccountsOverview

    var body: some View {
        // Siri's sheet is short and renders text large: keep rows to one line and let the amount win the width.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(overview.netWorth.formatted)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                ForEach(overview.accounts, id: \.id) { account in
                    AccountBalanceRow(account: account)
                }
            }

            Button(intent: OpenSectionIntent(section: .accounts)) {
                Label("Open aiBank", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
    }
}

private struct AccountBalanceRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(systemName: account.kind.symbolName, size: 26)
            Text(account.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            MoneyText(money: account.balance)
                .font(.subheadline.weight(.semibold))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName), \(account.kind.title), \(account.balance.formatted)")
    }
}

// MARK: - Review before moving money

/// Shown by `requestConfirmation(actionName:snippetIntent:)` before a payment or e-Transfer goes out.
/// Parameters are plain display strings, already formatted from validated domain values by the calling intent,
/// so perform() is a pure render and safe for the system to re-run.
struct PaymentReviewSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Review Payment"
    static let isDiscoverable = false

    @Parameter(title: "Headline") var headline: String
    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "To") var to: String
    @Parameter(title: "To Detail") var toDetail: String
    @Parameter(title: "From") var from: String
    @Parameter(title: "When") var when: String

    init() {}

    init(headline: String, amount: String, to: String, toDetail: String, from: String, when: String) {
        self.headline = headline
        self.amount = amount
        self.to = to
        self.toDetail = toDetail
        self.from = from
        self.when = when
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: PaymentReviewSnippetView(headline: headline, amount: amount, to: to, toDetail: toDetail,
                                               from: from, when: when))
    }
}

extension PaymentReviewSnippetIntent {
    static func bill(_ payment: BillPayment, fromAccountName: String) -> PaymentReviewSnippetIntent {
        PaymentReviewSnippetIntent(
            headline: "You're paying",
            amount: payment.amount.formatted,
            to: payment.payee.displayName,
            toDetail: payment.payee.displayName == payment.payee.biller.name
                ? payment.payee.maskedAccountNumber
                : "\(payment.payee.biller.name) · \(payment.payee.maskedAccountNumber)",
            from: fromAccountName,
            when: payment.isImmediate ? "Today" : payment.payOn.formatted(date: .long, time: .omitted))
    }

    static func eTransfer(_ transfer: ETransfer, fromAccountName: String) -> PaymentReviewSnippetIntent {
        PaymentReviewSnippetIntent(
            headline: "You're sending",
            amount: transfer.amount.formatted,
            to: transfer.recipient.name,
            toDetail: transfer.recipient.hasAutodeposit ? "Autodeposit" : "Protected by your security question",
            from: fromAccountName,
            when: "Now")
    }
}

struct PaymentReviewSnippetView: View {
    let headline: String
    let amount: String
    let to: String
    let toDetail: String
    let from: String
    let when: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline).foregroundStyle(.secondary)
                Text(amount)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            Divider()

            VStack(spacing: 8) {
                ReviewRow(label: "To") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(to)
                        Text(toDetail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ReviewRow(label: "From") { Text(from) }
                ReviewRow(label: "When") { Text(when) }
            }
        }
        .padding(16)
    }
}

private struct ReviewRow<Value: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value.multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Receipts

struct ReceiptSnippetView: View {
    struct Line: Identifiable {
        let label: LocalizedStringResource
        let value: String
        var id: String { "\(label.key)" }
    }

    let headline: LocalizedStringResource
    let amount: Money
    let lines: [Line]

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.positive)
                    .accessibilityHidden(true)
                Text(headline).font(.headline)
                Text(amount.formatted)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Divider()

            VStack(spacing: 8) {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(line.value).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
    }
}

extension ReceiptSnippetView {
    nonisolated init(_ receipt: ETransferReceipt, fromAccountName: String) {
        self.init(
            headline: "e-Transfer sent",
            amount: receipt.transfer.amount,
            lines: [
                Line(label: "To", value: receipt.transfer.recipient.name),
                Line(label: "From", value: fromAccountName),
                Line(label: "Confirmation", value: receipt.confirmationNumber),
                Line(label: "Sent", value: receipt.sentAt.formatted(date: .abbreviated, time: .shortened)),
                Line(label: "Balance after", value: receipt.sourceBalanceAfter.formatted),
            ])
    }

    nonisolated init(_ receipt: BillPaymentReceipt, fromAccountName: String) {
        let isCompleted = receipt.status == .completed
        let payee = receipt.payment.payee
        let payeeText = payee.displayName == payee.biller.name ? payee.displayName : "\(payee.displayName) · \(payee.biller.name)"
        self.init(
            headline: isCompleted ? "Bill paid" : "Payment scheduled",
            amount: receipt.payment.amount,
            lines: [
                Line(label: "To", value: payeeText),
                Line(label: "From", value: fromAccountName),
                Line(label: "Confirmation", value: receipt.confirmationNumber),
                Line(label: isCompleted ? "Paid" : "Pays on",
                     value: isCompleted
                        ? receipt.processedAt.formatted(date: .abbreviated, time: .shortened)
                        : receipt.payment.payOn.formatted(date: .long, time: .omitted)),
                Line(label: "Balance after", value: receipt.sourceBalanceAfter.formatted),
            ])
    }
}

// MARK: - Previews (driven by the in-process fake backend, so the cards show real seed data)

#if DEBUG
import AIBankBoundary

private struct SnippetPreviewSamples: Sendable {
    let overview: AccountsOverview
    let bill: BillPaymentReceipt
    let eTransfer: ETransferReceipt
    let payment: BillPayment
    let transfer: ETransfer
    let sourceName: String

    static func load() async throws -> SnippetPreviewSamples {
        let client = FakeBackend.client(latency: .zero)
        guard case .success(let credentials) = SignInRules.credentials(cardText: FakeBackend.demoCardNumber,
                                                                      password: FakeBackend.demoPassword)
        else { throw BankIntentError.invalid("Demo credentials rejected") }
        _ = try await client.signIn(credentials)

        let accounts = try await client.accounts()
        guard let source = AccountsOverview(accounts: accounts).billPaySources.first,
              let payee = try await client.payees().first,
              let recipient = try await client.recipients().first(where: \.hasAutodeposit)
        else { throw BankIntentError.invalid("Seed data is missing a source, payee or recipient") }

        let billDraft = BillPaymentDraft(sourceID: source.id, payeeID: payee.id, amountText: "79.00", scheduledDate: nil)
        let payment = try billDraft.validate(accounts: accounts, payees: try await client.payees(),
                                             now: .now, calendar: .current).get()
        let transferDraft = ETransferDraft(sourceID: source.id, recipientID: recipient.id, amountText: "25.00",
                                           message: "", question: "", answer: "")
        let transfer = try transferDraft.validate(accounts: accounts, recipients: try await client.recipients(),
                                                  sentToday: .zero()).get()

        return SnippetPreviewSamples(
            overview: AccountsOverview(accounts: try await client.accounts()),
            bill: try await client.payBill(payment),
            eTransfer: try await client.sendETransfer(transfer),
            payment: payment,
            transfer: transfer,
            sourceName: source.displayName)
    }
}

private struct SnippetPreviewHost<Card: View>: View {
    @ViewBuilder let card: (SnippetPreviewSamples) -> Card
    @State private var samples: SnippetPreviewSamples?

    var body: some View {
        Group {
            if let samples { card(samples) } else { ProgressView() }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding()
        .task { samples = try? await SnippetPreviewSamples.load() }
    }
}

#Preview("Balances") {
    SnippetPreviewHost { BalancesSnippetView(overview: $0.overview) }
}

#Preview("Bill review") {
    SnippetPreviewHost { samples in
        let review = PaymentReviewSnippetIntent.bill(samples.payment, fromAccountName: samples.sourceName)
        PaymentReviewSnippetView(headline: review.headline, amount: review.amount, to: review.to,
                                 toDetail: review.toDetail, from: review.from, when: review.when)
    }
}

#Preview("e-Transfer review") {
    SnippetPreviewHost { samples in
        let review = PaymentReviewSnippetIntent.eTransfer(samples.transfer, fromAccountName: samples.sourceName)
        PaymentReviewSnippetView(headline: review.headline, amount: review.amount, to: review.to,
                                 toDetail: review.toDetail, from: review.from, when: review.when)
    }
}

#Preview("Bill receipt") {
    SnippetPreviewHost { ReceiptSnippetView($0.bill, fromAccountName: $0.sourceName) }
}

#Preview("e-Transfer receipt") {
    SnippetPreviewHost { ReceiptSnippetView($0.eTransfer, fromAccountName: $0.sourceName) }
}
#endif
