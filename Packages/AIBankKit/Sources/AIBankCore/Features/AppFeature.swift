import Foundation

/// Descriptions of work for the shell. Plain values: comparable in tests, never closures.
public enum BankEffect: Equatable, Sendable {
    case signIn(Credentials)
    case signOut
    case loadAccounts
    case loadTransactions(Account.ID)
    case loadRecipients
    case loadPayees
    case loadATMs
    case sendETransfer(ETransfer)
    case payBill(BillPayment)
}

public enum AppTab: String, CaseIterable, Sendable, Equatable, Hashable {
    case accounts, interac, bills, atms

    public var title: String {
        switch self {
        case .accounts: "Accounts"
        case .interac: "Interac e-Transfer"
        case .bills: "Pay Bills"
        case .atms: "ATMs"
        }
    }

    public var shortTitle: String {
        switch self {
        case .accounts: "Accounts"
        case .interac: "e-Transfer"
        case .bills: "Bills"
        case .atms: "ATMs"
        }
    }
}

public struct SessionState: Equatable, Sendable {
    /// Every fresh launch starts signed out: a session never outlives the process that signed in.
    public enum Phase: Equatable, Sendable {
        case signedOut
        case signedIn(Session)
    }

    public var phase: Phase = .signedOut
    public var cardText = ""
    public var password = ""
    public var isSubmitting = false
    public var errorMessage: String?
    public var failedAttempts = 0
    public var lockedUntil: Date?
    /// When the app last went to the background while signed in.
    public var backgroundedAt: Date?

    public init() {}

    public var session: Session? {
        if case .signedIn(let s) = phase { s } else { nil }
    }

    public func isLocked(at now: Date) -> Bool { lockedUntil.map { now < $0 } ?? false }
}

public enum SignInAction: Sendable {
    case cardTextChanged(String)
    case passwordChanged(String)
    case submitTapped(now: Date)
}

public enum AppFeature: Feature {
    public struct State: Equatable, Sendable {
        public var session = SessionState()
        public var selectedTab: AppTab = .accounts
        public var accounts: AccountsState
        public var transfer = TransferState()
        public var bills = BillsState()
        public var atms: ATMState

        public init(now: Date, calendar: Calendar) {
            self.accounts = AccountsState(calendar: calendar)
            self.atms = ATMState(now: now, calendar: calendar)
        }

        /// Signed-out copy that keeps the sign-in form's memory (failed attempts, lockout).
        fileprivate func signedOut(now: Date, calendar: Calendar) -> State {
            var fresh = State(now: now, calendar: calendar)
            fresh.session.phase = .signedOut
            fresh.session.failedAttempts = session.failedAttempts
            fresh.session.lockedUntil = session.lockedUntil
            return fresh
        }
    }

    public enum Action: Sendable {
        case signIn(SignInAction)
        case signInFinished(Result<Session, BankError>, now: Date)
        case signOutTapped(now: Date)
        case tabSelected(AppTab)
        case becameActive(now: Date)
        case movedToBackground(now: Date)
        /// Something outside the screens (a Siri tool) was told by the server that there is no session.
        case serverEndedSession(BankError, now: Date)
        case accounts(AccountsAction)
        case transfer(TransferAction)
        case bills(BillsAction)
        case atms(ATMAction)
    }

    public typealias Effect = BankEffect
    public typealias Environment = BankEnvironment

    // MARK: - Reduce (pure)

    public static func reduce(_ state: State, _ action: Action) -> Reduced<State, Effect> {
        var s = state
        var effects: [Effect] = []
        let calendar = state.accounts.calendar

        switch action {
        case .signIn(.cardTextChanged(let text)):
            s.session.cardText = CardNumber.formatTyping(text)
            s.session.errorMessage = nil

        case .signIn(.passwordChanged(let text)):
            s.session.password = text
            s.session.errorMessage = nil

        case .signIn(.submitTapped(let now)):
            guard !s.session.isSubmitting else { break }
            if s.session.isLocked(at: now) {
                s.session.errorMessage = BankError.accountLocked.message
                break
            }
            switch SignInRules.credentials(cardText: s.session.cardText, password: s.session.password) {
            case .success(let credentials):
                s.session.isSubmitting = true
                s.session.errorMessage = nil
                effects = [.signIn(credentials)]
            case .failure(let issue):
                s.session.errorMessage = issue.message
            }

        case .signInFinished(.success(let session), _):
            s.session.isSubmitting = false
            s.session.phase = .signedIn(session)
            s.session.password = ""
            s.session.cardText = ""
            s.session.errorMessage = nil
            s.session.failedAttempts = 0
            s.session.lockedUntil = nil
            s.selectedTab = .accounts
            effects = refreshEffects(for: s)

        case .signInFinished(.failure(let error), let now):
            s.session.isSubmitting = false
            s.session.password = ""
            if error == .invalidCredentials {
                s.session.failedAttempts += 1
                if s.session.failedAttempts >= SignInRules.maxFailedAttempts {
                    s.session.lockedUntil = now.addingTimeInterval(SignInRules.lockoutDuration)
                    s.session.failedAttempts = 0
                    s.session.errorMessage = BankError.accountLocked.message
                } else {
                    s.session.errorMessage = error.message
                }
            } else {
                s.session.errorMessage = error.message
            }

        case .signOutTapped(let now):
            s = s.signedOut(now: now, calendar: calendar)
            effects = [.signOut]

        case .tabSelected(let tab):
            s.selectedTab = tab

        case .movedToBackground(let now):
            if s.session.session != nil { s.session.backgroundedAt = now }

        case .becameActive(let now):
            guard s.session.session != nil else { break }
            if let away = s.session.backgroundedAt, now.timeIntervalSince(away) >= SignInRules.idleTimeout {
                s = s.signedOut(now: now, calendar: calendar)
                s.session.errorMessage = BankError.sessionExpired.message
                effects = [.signOut]
            } else {
                s.session.backgroundedAt = nil
                // The refresh doubles as a server check: if the session lapsed while we were away, it signs us out.
                effects = [.loadAccounts]
            }

        case .serverEndedSession(let error, let now):
            // Already on the sign-in screen: leave whatever the person has typed alone.
            guard s.session.session != nil else { break }
            s = signOutIfExpired(s, error, now)

        case .accounts(let a):
            let r = AccountsFeature.reduce(s.accounts, a)
            s.accounts = r.state
            effects = r.effects
            s = signOutIfExpired(s, a.failure, state.atms.now)

        case .transfer(let a):
            let r = TransferFeature.reduce(
                s.transfer, a, accounts: s.accounts.overview?.accounts ?? [],
                knownTransactions: s.accounts.knownTransactions, calendar: calendar)
            s.transfer = r.state
            effects = r.effects
            // Money moved: balances and the source account's history are now stale.
            if case .sendFinished(.success(let receipt)) = a {
                effects += [.loadAccounts, .loadTransactions(receipt.transfer.source)]
            }
            if case .appeared = a, s.accounts.overview == nil { effects.append(.loadAccounts) }
            s = signOutIfExpired(s, a.failure, state.atms.now)

        case .bills(let a):
            let r = BillsFeature.reduce(s.bills, a, accounts: s.accounts.overview?.accounts ?? [], calendar: calendar)
            s.bills = r.state
            effects = r.effects
            if case .payFinished(.success(let receipt)) = a {
                effects += [.loadAccounts, .loadTransactions(receipt.payment.source)]
            }
            if case .appeared = a, s.accounts.overview == nil { effects.append(.loadAccounts) }
            s = signOutIfExpired(s, a.failure, state.atms.now)

        case .atms(let a):
            let r = ATMFeature.reduce(s.atms, a)
            s.atms = r.state
            effects = r.effects
            s = signOutIfExpired(s, a.failure, state.atms.now)
        }
        return Reduced(s, effects)
    }

    private static func refreshEffects(for state: State) -> [Effect] { [.loadAccounts] }

    /// If the server says the session is gone, drop back to the sign-in screen.
    private static func signOutIfExpired(_ state: State, _ error: BankError?, _ now: Date) -> State {
        guard let error, error == .sessionExpired || error == .notSignedIn else { return state }
        var out = state.signedOut(now: now, calendar: state.accounts.calendar)
        out.session.errorMessage = error.message
        return out
    }

    // MARK: - Perform (impure)

    public static func perform(_ effect: Effect, _ env: Environment) async -> [Action] {
        let client = env.client
        switch effect {
        case .signIn(let credentials):
            do { return [.signInFinished(.success(try await client.signIn(credentials)), now: env.now())] }
            catch { return [.signInFinished(.failure(.wrap(error)), now: env.now())] }

        case .signOut:
            try? await client.signOut()
            return []

        case .loadAccounts:
            return [.accounts(.loaded(await result { try await client.accounts() }))]

        case .loadTransactions(let id):
            return [.accounts(.transactionsLoaded(id, await result { try await client.transactions(id) }))]

        case .loadRecipients:
            return [.transfer(.recipientsLoaded(await result { try await client.recipients() }))]

        case .loadPayees:
            return [.bills(.payeesLoaded(await result { try await client.payees() }))]

        case .loadATMs:
            return [.atms(.loaded(await result { try await client.atms() }))]

        case .sendETransfer(let transfer):
            return [.transfer(.sendFinished(await result { try await client.sendETransfer(transfer) }))]

        case .payBill(let payment):
            return [.bills(.payFinished(await result { try await client.payBill(payment) }))]
        }
    }

    private static func result<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, BankError> {
        do { return .success(try await work()) } catch { return .failure(.wrap(error)) }
    }
}
