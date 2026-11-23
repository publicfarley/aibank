import Foundation
import Testing
import AIBankCore
@testable import AIBankBoundary

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ s: TimeInterval) { lock.withLock { current = current.addingTimeInterval(s) } }
}

final class Disk: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var persistence: Persistence {
        Persistence(load: { self.lock.withLock { self.data } }, save: { d in self.lock.withLock { self.data = d } })
    }
}

func makeClient(clock: Clock = Clock(), disk: Disk = Disk()) -> BankClient {
    FakeBackend.client(now: { clock.now }, persistence: disk.persistence, latency: .zero)
}

let demo = Credentials(card: CardNumber(FakeBackend.demoCardNumber)!, password: FakeBackend.demoPassword)

@Suite struct FakeBackendTests {
    @Test func requestsFailUntilSignedIn() async throws {
        let client = makeClient()
        await #expect(throws: BankError.notSignedIn) { try await client.accounts() }
    }

    @Test func wrongPasswordIsRejected() async {
        let client = makeClient()
        let bad = Credentials(card: demo.card, password: "nope-nope")
        await #expect(throws: BankError.invalidCredentials) { try await client.signIn(bad) }
    }

    @Test func seedDataParsesIntoDomain() async throws {
        let client = makeClient()
        _ = try await client.signIn(demo)
        let accounts = try await client.accounts()
        #expect(accounts.count == 5)
        #expect(AccountsOverview(accounts: accounts).netWorth.isPositive)
        let txns = try await client.transactions("acct-chq-001")
        #expect(!txns.isEmpty)
        #expect(try await client.recipients().count == 4)
        #expect(try await client.payees().count == 6)
        #expect(try await client.atms().count == 10)
    }

    @Test func unknownAccountIsNotFound() async throws {
        let client = makeClient()
        _ = try await client.signIn(demo)
        await #expect(throws: BankError.self) { try await client.transactions("nope") }
    }

    @Test func eTransferMovesMoneyAndWritesALedgerEntry() async throws {
        let client = makeClient()
        _ = try await client.signIn(demo)
        let accounts = try await client.accounts()
        let recipients = try await client.recipients()
        let draft = ETransferDraft(sourceID: "acct-chq-001", recipientID: "rcpt-001", amountText: "100.00", message: "Lunch")
        let transfer = try draft.validate(accounts: accounts, recipients: recipients).get()

        let before = try #require(accounts.first { $0.id == "acct-chq-001" }).balance
        let receipt = try await client.sendETransfer(transfer)
        #expect(receipt.sourceBalanceAfter == before - .cad(10_000))

        let after = try await client.accounts().first { $0.id == "acct-chq-001" }
        #expect(after?.balance == before - .cad(10_000))
        let txns = try await client.transactions("acct-chq-001")
        #expect(txns.contains { $0.kind == .eTransferSent && $0.amount == .cad(-10_000) && $0.detail == "Lunch" })
    }

    @Test func serverEnforcesFundsEvenIfTheClientDidNot() async throws {
        let client = makeClient()
        _ = try await client.signIn(demo)
        let accounts = try await client.accounts()
        let recipients = try await client.recipients()
        // Savings has $8,450.12; build a valid transfer then ask for more via a second, bigger draft on a poorer view.
        let tiny = Account(id: "acct-chq-001", kind: .chequing, nickname: "x", number: AccountNumber("5012348801")!,
                           balance: .cad(100_000_000))   // lies about its balance to the validator
        let draft = ETransferDraft(sourceID: "acct-chq-001", recipientID: "rcpt-001", amountText: "2999.00")
        let transfer = try draft.validate(accounts: [tiny], recipients: recipients).get()
        _ = accounts
        // 4,823.67 + 500 overdraft is enough for 2,999, so first succeeds...
        _ = try await client.sendETransfer(transfer)
        // ...and the second would overdraw (4,823.67 - 2,999 = 1,824.68 left; +500 overdraft < 2,999).
        await #expect(throws: BankError.insufficientFunds) { try await client.sendETransfer(transfer) }
    }

    @Test func billPaymentTodayPostsAndFutureIsScheduled() async throws {
        let clock = Clock()
        let client = makeClient(clock: clock)
        _ = try await client.signIn(demo)
        let accounts = try await client.accounts()
        let payees = try await client.payees()
        let cal = Calendar.current

        var draft = BillPaymentDraft(sourceID: "acct-chq-001", payeeID: "payee-001", amountText: "92.40")
        let today = try draft.validate(accounts: accounts, payees: payees, now: clock.now, calendar: cal).get()
        #expect(try await client.payBill(today).status == .completed)

        draft.scheduledDate = cal.date(byAdding: .day, value: 5, to: clock.now)
        let later = try draft.validate(accounts: accounts, payees: payees, now: clock.now, calendar: cal).get()
        let receipt = try await client.payBill(later)
        #expect(receipt.status == .scheduled)
    }

    @Test func stateSurvivesRestartButIdleSessionsExpire() async throws {
        let clock = Clock(), disk = Disk()
        let first = makeClient(clock: clock, disk: disk)
        _ = try await first.signIn(demo)

        // "Relaunch": a brand new server reading the same disk. Siri can still reach a live session.
        let second = makeClient(clock: clock, disk: disk)
        #expect(try await second.accounts().count == 5)

        clock.advance(SignInRules.idleTimeout + 1)
        await #expect(throws: BankError.sessionExpired) { try await second.accounts() }
        await #expect(throws: BankError.notSignedIn) { try await second.accounts() }
    }

    @Test func activityKeepsTheSessionAlive() async throws {
        let clock = Clock()
        let client = makeClient(clock: clock)
        _ = try await client.signIn(demo)
        for _ in 0..<4 {
            clock.advance(SignInRules.idleTimeout - 60)
            #expect(try await client.accounts().count == 5)
        }
    }

    @Test func thirtyIdleMinutesExpireTheSession() async throws {
        let clock = Clock()
        let client = makeClient(clock: clock)
        _ = try await client.signIn(demo)
        clock.advance(SignInRules.idleTimeout)
        await #expect(throws: BankError.sessionExpired) { try await client.accounts() }
    }
}

@Suite struct ParsingTests {
    @Test func malformedWireDataIsRejectedAtTheBoundary() {
        let bad = AccountDTO(id: "a", kind: "chequing", nickname: "", number: "5012348801", currency: "CAD",
                             balance: "12.345", borrowingLimit: "0.00", interestRateBasisPoints: 0)
        #expect(throws: BoundaryError.self) { try Account(dto: bad) }
        var worse = bad; worse.balance = "1.00"; worse.kind = "piggybank"
        #expect(throws: BoundaryError.self) { try Account(dto: worse) }
    }
}
