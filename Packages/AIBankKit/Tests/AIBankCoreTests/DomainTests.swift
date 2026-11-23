import Foundation
import Testing
@testable import AIBankCore

@Suite struct MoneyTests {
    @Test func parsesUserText() {
        #expect(Money(string: "1,234.5") == .cad(123_450))
        #expect(Money(string: "$12") == .cad(1_200))
        #expect(Money(string: ".5") == .cad(50))
        #expect(Money(string: "-3.07") == .cad(-307))
    }

    @Test(arguments: ["", "abc", "1.234", "1.2.3", "$", "1e5", "--1"])
    func rejectsMalformedText(_ text: String) {
        #expect(Money(string: text) == nil)
    }

    @Test func formatsWithGroupingAndSign() {
        #expect(Money.cad(123_456_789).formatted == "$1,234,567.89")
        #expect(Money.cad(-2_000).formatted == "-$20.00")
        #expect(Money.cad(5).formatted == "$0.05")
        #expect(Money.cad(-5).decimalString == "-0.05")
    }

    @Test func roundTripsThroughDecimalString() {
        for cents: Int64 in [0, 1, 99, 100, 123_456, -4_321] {
            #expect(Money(string: Money.cad(cents).decimalString) == .cad(cents))
        }
    }
}

@Suite struct AccountTests {
    @Test func availableFundsIncludeBorrowingRoom() {
        #expect(Fixture.chequing.availableFunds == .cad(150_000))
        #expect(Fixture.card.availableFunds == .cad(880_000))
        #expect(Fixture.card.amountOwed == .cad(120_000))
    }

    @Test func overviewSeparatesDepositsFromDebt() {
        let overview = AccountsOverview(accounts: Fixture.accounts)
        #expect(overview.totalDeposits == .cad(600_000))
        #expect(overview.totalOwed == .cad(120_000))
        #expect(overview.netWorth == .cad(480_000))
        #expect(overview.accounts.map(\.id.rawValue) == ["chq", "sav", "cc"])
        #expect(overview.eTransferSources.map(\.id.rawValue) == ["chq", "sav"])
    }
}

@Suite struct ETransferRuleTests {
    func draft(amount: String = "25.00", recipient: Recipient.ID? = "sam", source: Account.ID? = "chq") -> ETransferDraft {
        ETransferDraft(sourceID: source, recipientID: recipient, amountText: amount)
    }

    @Test func validDraftBecomesATransfer() throws {
        let transfer = try draft().validate(accounts: Fixture.accounts, recipients: Fixture.recipients).get()
        #expect(transfer.amount == .cad(2_500))
        #expect(transfer.recipient == Fixture.sam)
        #expect(transfer.challenge == nil)
    }

    @Test func reportsEveryProblemAtOnce() {
        let result = draft(amount: "", recipient: nil, source: nil).validate(accounts: Fixture.accounts, recipients: Fixture.recipients)
        guard case .failure(let f) = result else { Issue.record("expected failure"); return }
        #expect(f.issues == [.noSourceAccount, .noRecipient, .invalidAmount])
    }

    @Test func creditCardsCannotSend() {
        guard case .failure(let f) = draft(source: "cc").validate(accounts: Fixture.accounts, recipients: Fixture.recipients) else {
            Issue.record("expected failure"); return
        }
        #expect(f.issues == [.ineligibleSource])
    }

    @Test func enforcesFundsAndLimits() {
        func issues(_ amount: String, sent: Money = .zero()) -> [ETransferIssue] {
            if case .failure(let f) = draft(amount: amount).validate(accounts: Fixture.accounts, recipients: Fixture.recipients, sentToday: sent) { return f.issues }
            return []
        }
        #expect(issues("1500.01") == [.insufficientFunds(available: .cad(150_000))])
        #expect(issues("0.00") == [.invalidAmount])
        #expect(issues("3000.01") == [.exceedsPerTransaction(.cad(300_000))])
        #expect(issues("10", sent: .cad(999_500)) == [.exceedsDaily(remaining: .cad(500))])
    }

    @Test func recipientsWithoutAutodepositNeedAValidChallenge() throws {
        var d = draft(recipient: "morgan")
        guard case .failure(let f) = d.validate(accounts: Fixture.accounts, recipients: Fixture.recipients) else { Issue.record("expected failure"); return }
        #expect(f.issues == [.missingSecurityQuestion, .invalidSecurityAnswer])

        d.question = "Favourite band?"; d.answer = "two words"
        guard case .failure(let f2) = d.validate(accounts: Fixture.accounts, recipients: Fixture.recipients) else { Issue.record("expected failure"); return }
        #expect(f2.issues == [.invalidSecurityAnswer])

        d.answer = "Rush"
        let ok = try d.validate(accounts: Fixture.accounts, recipients: Fixture.recipients).get()
        #expect(ok.challenge == SecurityChallenge(question: "Favourite band?", answer: "Rush"))
    }
}

@Suite struct BillPaymentRuleTests {
    @Test func scheduledAndImmediatePaymentsAreDistinguished() throws {
        let tomorrow = Fixture.calendar.date(byAdding: .day, value: 1, to: Fixture.now)!
        var d = BillPaymentDraft(sourceID: "chq", payeeID: "p1", amountText: "84.50")
        #expect(try d.validate(accounts: Fixture.accounts, payees: [Fixture.hydroPayee], now: Fixture.now, calendar: Fixture.calendar).get().isImmediate)
        d.scheduledDate = tomorrow
        #expect(try !d.validate(accounts: Fixture.accounts, payees: [Fixture.hydroPayee], now: Fixture.now, calendar: Fixture.calendar).get().isImmediate)
    }

    @Test func rejectsPastAndDistantDates() {
        let past = Fixture.calendar.date(byAdding: .day, value: -2, to: Fixture.now)!
        let far = Fixture.calendar.date(byAdding: .year, value: 2, to: Fixture.now)!
        for (date, issue) in [(past, BillPaymentIssue.dateInPast), (far, .dateTooFarAhead)] {
            let d = BillPaymentDraft(sourceID: "chq", payeeID: "p1", amountText: "10", scheduledDate: date)
            guard case .failure(let f) = d.validate(accounts: Fixture.accounts, payees: [Fixture.hydroPayee], now: Fixture.now, calendar: Fixture.calendar) else {
                Issue.record("expected failure"); return
            }
            #expect(f.issues == [issue])
        }
    }
}

@Suite struct ATMTests {
    let here = Coordinate(latitude: 43.6487, longitude: -79.3815)
    let near = ATM(id: "near", name: "Near", network: .aiBank, address: "", city: "", coordinate: .init(latitude: 43.6490, longitude: -79.3815),
                   services: [.cashWithdrawal, .deposit], hours: .init(opensAtMinute: 6 * 60, closesAtMinute: 22 * 60))
    let far = ATM(id: "far", name: "Far", network: .partner, address: "", city: "", coordinate: .init(latitude: 43.7, longitude: -79.4),
                  services: [.cashWithdrawal, .open24Hours], hours: .init(opensAtMinute: 0, closesAtMinute: 0))

    @Test func distanceIsRoughlyRight() {
        let d = here.distance(to: .init(latitude: 43.6577, longitude: -79.3815))   // 0.009° lat ≈ 1 km
        #expect(abs(d - 1_000) < 10)
    }

    @Test func sortsNearestFirstAndFilters() {
        let noon = Fixture.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Fixture.now)!
        let all = ATMFinder.nearby([far, near], to: here, filter: .init(), now: noon, calendar: Fixture.calendar)
        #expect(all.map(\.id.rawValue) == ["near", "far"])
        let deposits = ATMFinder.nearby([far, near], to: here, filter: .init(requiredServices: .deposit), now: noon, calendar: Fixture.calendar)
        #expect(deposits.map(\.id.rawValue) == ["near"])
    }

    @Test func openNowHonoursHoursAnd24HourMachines() {
        let threeAM = Fixture.calendar.date(bySettingHour: 3, minute: 0, second: 0, of: Fixture.now)!
        let open = ATMFinder.nearby([far, near], to: here, filter: .init(onlyOpenNow: true), now: threeAM, calendar: Fixture.calendar)
        #expect(open.map(\.id.rawValue) == ["far"])
    }
}

@Suite struct AuthRuleTests {
    @Test func cardNumberFormattingAsYouType() {
        #expect(CardNumber.formatTyping("45001234") == "4500 1234")
        #expect(CardNumber.formatTyping("4500-1234 5678 9010 99") == "4500 1234 5678 9010")
    }

    @Test func credentialsAreParsedNotValidated() {
        #expect(SignInRules.credentials(cardText: "4500 1234", password: "secret1") == .failure(.cardNumberIncomplete))
        #expect(SignInRules.credentials(cardText: "4500 1234 5678 9010", password: "abc") == .failure(.passwordTooShort))
        #expect((try? SignInRules.credentials(cardText: "4500 1234 5678 9010", password: "secret1").get()) != nil)
    }
}
