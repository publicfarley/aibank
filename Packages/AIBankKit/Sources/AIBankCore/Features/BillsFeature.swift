import Foundation

public struct BillsState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case editing
        case reviewing(BillPayment)
        case paying(BillPayment)
        case completed(BillPaymentReceipt)
        case failed(BillPayment, BankError)
    }

    public var payees: LoadState<[Payee]> = .idle
    public var draft = BillPaymentDraft()
    public var issues: [BillPaymentIssue] = []
    public var showsIssues = false
    public var step: Step = .editing

    public init() {}

    public func payee(_ id: Payee.ID?) -> Payee? {
        guard let id else { return nil }
        return payees.value?.first { $0.id == id }
    }

    /// Payees grouped by category for the list, categories alphabetical.
    public var payeesByCategory: [(category: BillerCategory, payees: [Payee])] {
        let groups = Dictionary(grouping: payees.value ?? []) { $0.biller.category }
        return groups.keys.sorted { $0.title < $1.title }.map { key in
            (category: key, payees: (groups[key] ?? []).sorted { $0.displayName < $1.displayName })
        }
    }
}

public enum BillsAction: Sendable {
    case appeared
    case payeesLoaded(Result<[Payee], BankError>)
    case draftChanged(BillPaymentDraft)
    case reviewTapped(now: Date)
    case editTapped
    case confirmTapped
    case payFinished(Result<BillPaymentReceipt, BankError>)
    case doneTapped

    var failure: BankError? {
        switch self {
        case .payeesLoaded(.failure(let e)), .payFinished(.failure(let e)): e
        default: nil
        }
    }
}

enum BillsFeature {
    static func reduce(_ state: BillsState, _ action: BillsAction, accounts: [Account], calendar: Calendar)
        -> Reduced<BillsState, BankEffect>
    {
        var s = state
        let eligible = accounts.filter { $0.kind.canPayBills }

        switch action {
        case .appeared:
            if s.draft.sourceID == nil { s.draft.sourceID = eligible.first?.id }
            if s.payees.value == nil { s.payees = .loading }
            return Reduced(s, [.loadPayees])

        case .payeesLoaded(.success(let list)):
            s.payees = .loaded(list)
            return Reduced(s)

        case .payeesLoaded(.failure(let error)):
            if s.payees.value == nil { s.payees = .failed(error) }
            return Reduced(s)

        case .draftChanged(let draft):
            s.draft = draft
            if s.showsIssues, case .failure(let issues) = draft.validate(
                accounts: accounts, payees: s.payees.value ?? [], now: draft.scheduledDate ?? .distantPast, calendar: calendar) {
                // Re-check only the structural issues live; date rules are rechecked on Review.
                s.issues = issues.issues.filter { $0 != .dateInPast }
            } else if s.showsIssues {
                s.issues = []
            }
            return Reduced(s)

        case .reviewTapped(let now):
            switch s.draft.validate(accounts: accounts, payees: s.payees.value ?? [], now: now, calendar: calendar) {
            case .success(let payment):
                s.issues = []
                s.showsIssues = false
                s.step = .reviewing(payment)
            case .failure(let failure):
                s.issues = failure.issues
                s.showsIssues = true
            }
            return Reduced(s)

        case .editTapped:
            s.step = .editing
            return Reduced(s)

        case .confirmTapped:
            switch s.step {
            case .reviewing(let p), .failed(let p, _):
                s.step = .paying(p)
                return Reduced(s, [.payBill(p)])
            default:
                return Reduced(s)
            }

        case .payFinished(.success(let receipt)):
            s.step = .completed(receipt)
            return Reduced(s)

        case .payFinished(.failure(let error)):
            if case .paying(let p) = s.step { s.step = .failed(p, error) }
            return Reduced(s)

        case .doneTapped:
            var fresh = BillsState()
            fresh.payees = s.payees
            fresh.draft.sourceID = s.draft.sourceID
            return Reduced(fresh)
        }
    }
}
