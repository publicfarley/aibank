import AIBankCore
import SwiftUI

struct BillPayView: View {
    let store: AppStore

    private var bills: BillsState { store.state.bills }
    private var accounts: [Account] { store.state.accounts.overview?.billPaySources ?? [] }

    private var draft: Binding<BillPaymentDraft> {
        Binding(get: { store.state.bills.draft }, set: { store.send(.bills(.draftChanged($0))) })
    }

    private var isScheduled: Binding<Bool> {
        Binding(
            get: { store.state.bills.draft.scheduledDate != nil },
            set: { on in
                var d = store.state.bills.draft
                d.scheduledDate = on ? Calendar.current.date(byAdding: .day, value: 1, to: .now) : nil
                store.send(.bills(.draftChanged(d)))
            })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch bills.step {
                case .editing: form
                case .reviewing(let p): review(p)
                case .paying(let p): ProgressStep(title: "Paying \(p.payee.displayName)…")
                case .completed(let r): success(r)
                case .failed(_, let error): failure(error)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Pay Bills")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { store.send(.bills(.appeared)) }
    }

    private var form: some View {
        Form {
            Section("Pay") {
                LoadStateView(state: bills.payees, retry: { store.send(.bills(.appeared)) }) { _ in
                    ForEach(bills.payeesByCategory, id: \.category) { group in
                        Section(group.category.title) {
                            ForEach(group.payees) { payee in payeeRow(payee) }
                        }
                    }
                }
            }

            Section("From") {
                Picker("Account", selection: draft.sourceID) {
                    ForEach(accounts) { a in
                        Text("\(a.displayName) · \(a.availableFunds.formatted)").tag(Account.ID?.some(a.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Amount") {
                HStack {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: draft.amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("billAmount")
                }
                if let last = bills.payee(bills.draft.payeeID)?.lastPayment {
                    Button("Use last payment · \(last.formatted)") { draft.wrappedValue.amountText = last.decimalString }
                        .font(.footnote)
                }
            }

            Section("When") {
                Toggle("Schedule for later", isOn: isScheduled)
                if let date = bills.draft.scheduledDate {
                    DatePicker("Pay on", selection: Binding(get: { date }, set: { draft.wrappedValue.scheduledDate = $0 }),
                               in: Date.now..., displayedComponents: .date)
                }
            }

            if bills.showsIssues, !bills.issues.isEmpty {
                Section {
                    ForEach(Array(bills.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline)
                    }
                }
            }

            Section {
                Button("Review") { store.send(.bills(.reviewTapped(now: .now))) }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(.init()).listRowBackground(Color.clear)
                    .accessibilityIdentifier("billReview")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func payeeRow(_ payee: Payee) -> some View {
        Button { draft.wrappedValue.payeeID = payee.id } label: {
            HStack(spacing: 12) {
                SymbolBadge(systemName: "doc.text")
                VStack(alignment: .leading) {
                    Text(payee.displayName).foregroundStyle(.primary)
                    Text("\(payee.biller.name) \(payee.maskedAccountNumber)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if bills.draft.payeeID == payee.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(bills.draft.payeeID == payee.id ? .isSelected : [])
        .accessibilityIdentifier("payee-\(payee.id.rawValue)")
    }

    private func review(_ p: BillPayment) -> some View {
        let source = store.state.accounts.overview?.account(p.source)
        return ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("You're paying").font(.subheadline).foregroundStyle(.secondary)
                        MoneyText(money: p.amount).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Divider()
                        line("To", "\(p.payee.displayName)\n\(p.payee.biller.name)")
                        line("Account number", p.payee.maskedAccountNumber)
                        line("From", source?.displayName ?? "—")
                        line("When", p.isImmediate ? "Today" : p.payOn.formatted(date: .long, time: .omitted))
                    }
                }
                Button(p.isImmediate ? "Pay \(p.amount.formatted)" : "Schedule \(p.amount.formatted)") {
                    store.send(.bills(.confirmTapped))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("billConfirm")
                Button("Edit") { store.send(.bills(.editTapped)) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    private func success(_ r: BillPaymentReceipt) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ResultHeader(symbol: "checkmark.circle.fill", tint: Theme.positive,
                             title: r.status == .completed ? "Bill paid" : "Payment scheduled",
                             subtitle: "\(r.payment.amount.formatted) to \(r.payment.payee.displayName)")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        line("Confirmation", r.confirmationNumber)
                        line(r.status == .completed ? "Paid" : "Will be paid",
                             r.status == .completed ? r.processedAt.formatted(date: .abbreviated, time: .shortened)
                                                    : r.payment.payOn.formatted(date: .long, time: .omitted))
                        line("Balance after", r.sourceBalanceAfter.formatted)
                    }
                }
                Button("Done") { store.send(.bills(.doneTapped)) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("billDone")
            }
            .padding(16)
        }
    }

    private func failure(_ error: BankError) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ResultHeader(symbol: "xmark.octagon.fill", tint: .red, title: "Payment not made", subtitle: error.message)
                Button("Try Again") { store.send(.bills(.confirmTapped)) }.buttonStyle(PrimaryButtonStyle())
                Button("Edit") { store.send(.bills(.editTapped)) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing).fontWeight(.medium)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
