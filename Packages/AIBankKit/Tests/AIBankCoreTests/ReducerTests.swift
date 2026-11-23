import Foundation
import Testing
@testable import AIBankCore

@Suite struct SignInReducerTests {
    @Test func freshLaunchAlwaysAsksToSignIn() {
        #expect(Fixture.initialState().session.phase == .signedOut)
    }

    @Test func shortTripToTheBackgroundKeepsTheSessionAndRefreshes() {
        var s = Fixture.signedIn()
        s = AppFeature.reduce(s, .movedToBackground(now: Fixture.now)).state
        let r = AppFeature.reduce(s, .becameActive(now: Fixture.now.addingTimeInterval(SignInRules.idleTimeout - 1)))
        #expect(r.state.session.session != nil)
        #expect(r.state.session.backgroundedAt == nil)
        #expect(r.effects == [.loadAccounts])
    }

    @Test func thirtyMinutesInTheBackgroundSignsOut() {
        var s = Fixture.signedIn()
        s = AppFeature.reduce(s, .movedToBackground(now: Fixture.now)).state
        let r = AppFeature.reduce(s, .becameActive(now: Fixture.now.addingTimeInterval(SignInRules.idleTimeout)))
        #expect(r.state.session.phase == .signedOut)
        #expect(r.state.session.errorMessage == BankError.sessionExpired.message)
        #expect(r.effects == [.signOut])
    }

    @Test func becomingActiveWhileSignedOutDoesNothing() {
        var s = Fixture.initialState()
        s = AppFeature.reduce(s, .movedToBackground(now: Fixture.now)).state
        let r = AppFeature.reduce(s, .becameActive(now: Fixture.now.addingTimeInterval(3_600)))
        #expect(r.state.session.backgroundedAt == nil)
        #expect(r.state.session.errorMessage == nil)
        #expect(r.effects.isEmpty)
    }

    @Test func siriFindingTheSessionGoneSignsTheAppOut() {
        let r = AppFeature.reduce(Fixture.signedIn(), .serverEndedSession(.sessionExpired, now: Fixture.now))
        #expect(r.state.session.phase == .signedOut)
        #expect(r.state.session.errorMessage == BankError.sessionExpired.message)
        #expect(r.effects.isEmpty)
    }

    @Test func siriFindingTheSessionGoneWhileSignedOutKeepsTheForm() {
        var s = Fixture.initialState()
        s.session.cardText = "4500 12"
        let r = AppFeature.reduce(s, .serverEndedSession(.notSignedIn, now: Fixture.now))
        #expect(r.state.session.phase == .signedOut)
        #expect(r.state.session.cardText == "4500 12")
        #expect(r.effects.isEmpty)
    }

    @Test func invalidFormNeverReachesTheNetwork() {
        var s = Fixture.initialState()
        s.session.cardText = "4500"
        let r = AppFeature.reduce(s, .signIn(.submitTapped(now: Fixture.now)))
        #expect(r.effects.isEmpty)
        #expect(r.state.session.errorMessage == SignInIssue.cardNumberIncomplete.message)
    }

    @Test func validFormEmitsSignInEffect() {
        var s = Fixture.initialState()
        s = AppFeature.reduce(s, .signIn(.cardTextChanged("4500123456789010"))).state
        s = AppFeature.reduce(s, .signIn(.passwordChanged("aibank1"))).state
        let r = AppFeature.reduce(s, .signIn(.submitTapped(now: Fixture.now)))
        #expect(r.state.session.isSubmitting)
        #expect(r.state.session.cardText == "4500 1234 5678 9010")
        #expect(r.effects == [.signIn(Credentials(card: CardNumber("4500123456789010")!, password: "aibank1"))])
    }

    @Test func threeBadPasswordsLockTheForm() {
        var s = Fixture.initialState()
        s.session.cardText = "4500 1234 5678 9010"
        for _ in 0..<3 {
            s = AppFeature.reduce(s, .signInFinished(.failure(.invalidCredentials), now: Fixture.now)).state
        }
        #expect(s.session.isLocked(at: Fixture.now))
        s.session.password = "aibank1"
        let r = AppFeature.reduce(s, .signIn(.submitTapped(now: Fixture.now)))
        #expect(r.effects.isEmpty)
        #expect(r.state.session.errorMessage == BankError.accountLocked.message)
        #expect(!r.state.session.isLocked(at: Fixture.now.addingTimeInterval(SignInRules.lockoutDuration + 1)))
    }

    @Test func successfulSignInLoadsAccounts() {
        let customer = Customer(id: "c", givenName: "J", familyName: "A", email: EmailAddress("j@example.com")!, memberSince: Fixture.now)
        let session = Session(customer: customer, expiresAt: Fixture.now.addingTimeInterval(60))
        let r = AppFeature.reduce(Fixture.initialState(), .signInFinished(.success(session), now: Fixture.now))
        #expect(r.state.session.session == session)
        #expect(r.effects == [.loadAccounts])
    }

    @Test func signOutClearsEverythingButKeepsLockout() {
        var s = Fixture.signedIn()
        s.session.lockedUntil = Fixture.now.addingTimeInterval(100)
        let r = AppFeature.reduce(s, .signOutTapped(now: Fixture.now))
        #expect(r.state.session.phase == .signedOut)
        #expect(r.state.accounts.accounts == .idle)
        #expect(r.state.session.lockedUntil != nil)
        #expect(r.effects == [.signOut])
    }

    @Test func expiredSessionOnAnyRequestReturnsToSignIn() {
        let r = AppFeature.reduce(Fixture.signedIn(), .accounts(.loaded(.failure(.sessionExpired))))
        #expect(r.state.session.phase == .signedOut)
        #expect(r.state.session.errorMessage == BankError.sessionExpired.message)
    }
}

@Suite struct AccountsReducerTests {
    @Test func selectingAnAccountNavigatesAndLoadsTransactions() {
        let r = AppFeature.reduce(Fixture.signedIn(), .accounts(.accountSelected("chq")))
        #expect(r.state.accounts.path == [.detail("chq")])
        #expect(r.state.accounts.history(for: "chq") == .loading)
        #expect(r.effects == [.loadTransactions("chq")])
    }

    @Test func failedRefreshKeepsStaleData() {
        let r = AppFeature.reduce(Fixture.signedIn(), .accounts(.loaded(.failure(.offline))))
        #expect(r.state.accounts.overview != nil)
    }

    @Test func leavingTransactionsResetsFilter() {
        var s = Fixture.signedIn()
        s.accounts.path = [.detail("chq"), .transactions("chq")]
        s.accounts.filter = TransactionFilter(searchText: "coffee")
        let r = AppFeature.reduce(s, .accounts(.pathChanged([.detail("chq")])))
        #expect(r.state.accounts.filter == TransactionFilter())
    }

    @Test func filterMatchesTitleDetailAndDirection() {
        let t = Transaction(id: "t", accountID: "chq", kind: .purchase, amount: .cad(-500), date: Fixture.now,
                            title: "Daily Grind Coffee", detail: "Latte", category: .dining)
        #expect(TransactionFilter(searchText: "grind").matches(t))
        #expect(TransactionFilter(searchText: "latte").matches(t))
        #expect(TransactionFilter(direction: .moneyOut).matches(t))
        #expect(!TransactionFilter(direction: .moneyIn).matches(t))
        #expect(!TransactionFilter(category: .groceries).matches(t))
    }
}

@Suite struct TransferReducerTests {
    func reduce(_ s: AppFeature.State, _ a: TransferAction) -> Reduced<AppFeature.State, BankEffect> {
        AppFeature.reduce(s, .transfer(a))
    }

    @Test func reviewWithBadDraftShowsIssuesAndStaysPut() {
        var s = Fixture.signedIn()
        s.transfer.draft.recipientID = nil
        let r = reduce(s, .reviewTapped(now: Fixture.now))
        #expect(r.state.transfer.step == .editing)
        #expect(r.state.transfer.issues.contains(.noRecipient))
        #expect(r.effects.isEmpty)
    }

    @Test func fullHappyPath() throws {
        var s = Fixture.signedIn()
        s.transfer.draft.recipientID = "sam"
        s.transfer.draft.amountText = "40"

        var r = reduce(s, .reviewTapped(now: Fixture.now))
        guard case .reviewing(let transfer) = r.state.transfer.step else { Issue.record("expected review"); return }

        r = reduce(r.state, .confirmTapped)
        #expect(r.state.transfer.step == .sending(transfer))
        #expect(r.effects == [.sendETransfer(transfer)])

        // Tapping again while sending must not send twice.
        #expect(reduce(r.state, .confirmTapped).effects.isEmpty)

        let receipt = ETransferReceipt(confirmationNumber: "CA1", transfer: transfer, sentAt: Fixture.now, sourceBalanceAfter: .cad(96_000))
        r = reduce(r.state, .sendFinished(.success(receipt)))
        #expect(r.state.transfer.step == .completed(receipt))
        #expect(r.effects == [.loadAccounts, .loadTransactions("chq")])
    }

    @Test func failedSendCanBeRetried() throws {
        var s = Fixture.signedIn()
        s.transfer.draft.recipientID = "sam"
        s.transfer.draft.amountText = "40"
        var r = reduce(s, .reviewTapped(now: Fixture.now))
        r = reduce(r.state, .confirmTapped)
        r = reduce(r.state, .sendFinished(.failure(.offline)))
        guard case .failed(let t, .offline) = r.state.transfer.step else { Issue.record("expected failure"); return }
        r = reduce(r.state, .confirmTapped)
        #expect(r.effects == [.sendETransfer(t)])
    }

    @Test func dailyLimitUsesKnownTransactions() {
        var s = Fixture.signedIn()
        let big = Transaction(id: "x", accountID: "chq", kind: .eTransferSent, amount: .cad(-999_900), date: Fixture.now,
                              title: "e-Transfer", category: .transfers)
        s.accounts.transactions["chq"] = .loaded(TransactionHistory([big]))
        s.transfer.draft.recipientID = "sam"
        s.transfer.draft.amountText = "5"
        let r = reduce(s, .reviewTapped(now: Fixture.now))
        #expect(r.state.transfer.issues == [.exceedsDaily(remaining: .cad(100))])
    }
}

@Suite struct BillsReducerTests {
    @Test func payingEmitsEffectAndRefreshesAccounts() {
        var s = Fixture.signedIn()
        s.bills.draft.payeeID = "p1"
        s.bills.draft.amountText = "84.50"
        var r = AppFeature.reduce(s, .bills(.reviewTapped(now: Fixture.now)))
        guard case .reviewing(let payment) = r.state.bills.step else { Issue.record("expected review"); return }
        r = AppFeature.reduce(r.state, .bills(.confirmTapped))
        #expect(r.effects == [.payBill(payment)])
        let receipt = BillPaymentReceipt(confirmationNumber: "CA2", payment: payment, status: .completed, processedAt: Fixture.now, sourceBalanceAfter: .cad(1))
        r = AppFeature.reduce(r.state, .bills(.payFinished(.success(receipt))))
        #expect(r.effects == [.loadAccounts, .loadTransactions("chq")])
    }
}

@Suite struct ATMReducerTests {
    @Test func filteringDropsHiddenSelection() {
        var s = Fixture.signedIn()
        let atm = ATM(id: "a", name: "A", network: .partner, address: "", city: "", coordinate: ATMState.defaultLocation,
                      services: [.cashWithdrawal], hours: .init(opensAtMinute: 0, closesAtMinute: 1440))
        s.atms.atms = .loaded([atm])
        s.atms.selectedID = "a"
        let r = AppFeature.reduce(s, .atms(.filterChanged(ATMFilter(network: .aiBank))))
        #expect(r.state.atms.selectedID == nil)
        #expect(r.state.atms.results.isEmpty)
    }
}
