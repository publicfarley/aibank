import AIBankCore
import SwiftUI

struct ETransferView: View {
    let store: AppStore

    private var transfer: TransferState { store.state.transfer }
    private var accounts: [Account] { store.state.accounts.overview?.eTransferSources ?? [] }

    private var draft: Binding<ETransferDraft> {
        Binding(get: { store.state.transfer.draft }, set: { store.send(.transfer(.draftChanged($0))) })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch transfer.step {
                case .editing: form
                case .reviewing(let t): review(t)
                case .sending(let t): ProgressStep(title: "Sending \(t.amount.formatted) to \(t.recipient.name)…")
                case .completed(let receipt): success(receipt)
                case .failed(let t, let error): failure(t, error)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Interac e-Transfer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { store.send(.transfer(.appeared)) }
    }

    // MARK: Editing

    private var form: some View {
        Form {
            Section("From") {
                Picker("Account", selection: draft.sourceID) {
                    ForEach(accounts) { a in
                        Text("\(a.displayName) · \(a.availableFunds.formatted)").tag(Account.ID?.some(a.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("etransferFrom")
            }

            Section("To") {
                LoadStateView(state: transfer.recipients, retry: { store.send(.transfer(.appeared)) }) { recipients in
                    ForEach(recipients) { r in
                        Button { draft.wrappedValue.recipientID = r.id } label: {
                            HStack(spacing: 12) {
                                Avatar(initials: r.initials)
                                VStack(alignment: .leading) {
                                    Text(r.name).foregroundStyle(.primary)
                                    Text(r.hasAutodeposit ? "Autodeposit" : "Security question").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if transfer.draft.recipientID == r.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(transfer.draft.recipientID == r.id ? .isSelected : [])
                        .accessibilityIdentifier("recipient-\(r.id.rawValue)")
                    }
                }
            }

            Section("Amount") {
                HStack {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: draft.amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("etransferAmount")
                }
                TextField("Message (optional)", text: draft.message, axis: .vertical)
                    .lineLimit(1...3)
            }

            if let recipient = transfer.recipient(transfer.draft.recipientID), !recipient.hasAutodeposit {
                Section {
                    TextField("Security question", text: draft.question)
                    TextField("Answer (no spaces)", text: draft.answer)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Security question") } footer: {
                    Text("\(recipient.name) will need the answer to deposit this money. Share it separately.")
                }
            }

            if transfer.showsIssues, !transfer.issues.isEmpty {
                Section {
                    ForEach(Array(transfer.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline)
                    }
                }
            }

            Section {
                Button("Review") { store.send(.transfer(.reviewTapped(now: .now))) }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(.init()).listRowBackground(Color.clear)
                    .accessibilityIdentifier("etransferReview")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Review, result

    private func review(_ t: ETransfer) -> some View {
        let source = store.state.accounts.overview?.account(t.source)
        return ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("You're sending").font(.subheadline).foregroundStyle(.secondary)
                        MoneyText(money: t.amount).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Divider()
                        line("To", "\(t.recipient.name)\n\(t.recipient.email.value)")
                        line("From", source?.displayName ?? "—")
                        if let m = t.message { line("Message", m) }
                        if let c = t.challenge { line("Security question", c.question) }
                        if t.recipient.hasAutodeposit { line("Delivery", "Deposited automatically") }
                    }
                }
                Button("Send \(t.amount.formatted)") { store.send(.transfer(.confirmTapped)) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("etransferConfirm")
                Button("Edit") { store.send(.transfer(.editTapped)) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    private func success(_ receipt: ETransferReceipt) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ResultHeader(symbol: "checkmark.circle.fill", tint: Theme.positive, title: "Money sent",
                             subtitle: "\(receipt.transfer.amount.formatted) to \(receipt.transfer.recipient.name)")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        line("Confirmation", receipt.confirmationNumber)
                        line("Sent", receipt.sentAt.formatted(date: .abbreviated, time: .shortened))
                        line("Balance after", receipt.sourceBalanceAfter.formatted)
                    }
                }
                Button("Done") { store.send(.transfer(.doneTapped)) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("etransferDone")
            }
            .padding(16)
        }
    }

    private func failure(_ t: ETransfer, _ error: BankError) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ResultHeader(symbol: "xmark.octagon.fill", tint: .red, title: "Transfer not sent", subtitle: error.message)
                Button("Try Again") { store.send(.transfer(.confirmTapped)) }.buttonStyle(PrimaryButtonStyle())
                Button("Edit") { store.send(.transfer(.editTapped)) }.buttonStyle(SecondaryButtonStyle())
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

// MARK: - Shared bits for the two money-movement flows

struct ProgressStep: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(title).font(.headline).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResultHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(tint).accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}
