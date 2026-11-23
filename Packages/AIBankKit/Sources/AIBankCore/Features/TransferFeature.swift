import Foundation

public struct TransferState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case editing
        case reviewing(ETransfer)
        case sending(ETransfer)
        case completed(ETransferReceipt)
        case failed(ETransfer, BankError)
    }

    public var recipients: LoadState<[Recipient]> = .idle
    public var draft = ETransferDraft()
    public var issues: [ETransferIssue] = []
    public var showsIssues = false
    public var step: Step = .editing
    public var limits: ETransferLimits = .standard

    public init() {}

    public func recipient(_ id: Recipient.ID?) -> Recipient? {
        guard let id else { return nil }
        return recipients.value?.first { $0.id == id }
    }
}

public enum TransferAction: Sendable {
    case appeared
    case recipientsLoaded(Result<[Recipient], BankError>)
    case draftChanged(ETransferDraft)
    case reviewTapped(now: Date)
    case editTapped
    case confirmTapped
    case sendFinished(Result<ETransferReceipt, BankError>)
    case doneTapped

    var failure: BankError? {
        switch self {
        case .recipientsLoaded(.failure(let e)), .sendFinished(.failure(let e)): e
        default: nil
        }
    }
}

enum TransferFeature {
    static func reduce(
        _ state: TransferState, _ action: TransferAction,
        accounts: [Account], knownTransactions: [Transaction], calendar: Calendar
    ) -> Reduced<TransferState, BankEffect> {
        var s = state
        let eligible = accounts.filter { $0.kind.canSendETransfer }

        switch action {
        case .appeared:
            if s.draft.sourceID == nil { s.draft.sourceID = eligible.first?.id }
            if s.recipients.value == nil { s.recipients = .loading }
            return Reduced(s, [.loadRecipients])

        case .recipientsLoaded(.success(let list)):
            s.recipients = .loaded(list)
            return Reduced(s)

        case .recipientsLoaded(.failure(let error)):
            if s.recipients.value == nil { s.recipients = .failed(error) }
            return Reduced(s)

        case .draftChanged(let draft):
            s.draft = draft
            if s.showsIssues { s.issues = revalidate(s, accounts, knownTransactions, calendar, now: nil) }
            return Reduced(s)

        case .reviewTapped(let now):
            switch s.draft.validate(accounts: accounts, recipients: s.recipients.value ?? [],
                                    sentToday: sentToday(knownTransactions, now, calendar), limits: s.limits) {
            case .success(let transfer):
                s.issues = []
                s.showsIssues = false
                s.step = .reviewing(transfer)
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
            case .reviewing(let t), .failed(let t, _):
                s.step = .sending(t)
                return Reduced(s, [.sendETransfer(t)])
            default:
                return Reduced(s)   // double tap or stale button: ignore
            }

        case .sendFinished(.success(let receipt)):
            s.step = .completed(receipt)
            return Reduced(s)

        case .sendFinished(.failure(let error)):
            if case .sending(let t) = s.step { s.step = .failed(t, error) }
            return Reduced(s)

        case .doneTapped:
            var fresh = TransferState()
            fresh.recipients = s.recipients
            fresh.draft.sourceID = s.draft.sourceID
            fresh.limits = s.limits
            return Reduced(fresh)
        }
    }

    private static func sentToday(_ txns: [Transaction], _ now: Date, _ calendar: Calendar) -> Money {
        TransactionHistory(txns).eTransfersSent(on: now, calendar: calendar)
    }

    private static func revalidate(_ s: TransferState, _ accounts: [Account], _ txns: [Transaction],
                                   _ calendar: Calendar, now: Date?) -> [ETransferIssue] {
        let today = now.map { sentToday(txns, $0, calendar) } ?? .zero()
        if case .failure(let issues) = s.draft.validate(accounts: accounts, recipients: s.recipients.value ?? [],
                                                        sentToday: today, limits: s.limits) { return issues.issues }
        return []
    }
}
