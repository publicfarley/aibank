import Foundation
@testable import AIBankCore

enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed instant
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }()

    static let chequing = Account(id: "chq", kind: .chequing, nickname: "Everyday", number: AccountNumber("5012348801")!,
                                  balance: .cad(100_000), borrowingLimit: .cad(50_000))
    static let savings = Account(id: "sav", kind: .savings, nickname: "Savings", number: AccountNumber("5012348902")!,
                                 balance: .cad(500_000))
    static let card = Account(id: "cc", kind: .creditCard, nickname: "Visa", number: AccountNumber("4500123456789010")!,
                              balance: .cad(-120_000), borrowingLimit: .cad(1_000_000))
    static let accounts = [chequing, savings, card]

    static let sam = Recipient(id: "sam", name: "Sam Patel", email: EmailAddress("sam@example.com")!, hasAutodeposit: true)
    static let morgan = Recipient(id: "morgan", name: "Morgan Lee", email: EmailAddress("morgan@example.com")!, hasAutodeposit: false)
    static let recipients = [sam, morgan]

    static let hydro = Biller(id: "hydro", name: "Hydro", category: .utilities, accountNumberLength: 10...10)
    static let hydroPayee = Payee(id: "p1", biller: hydro, accountNumber: "4400128891", nickname: nil, lastPayment: nil)

    static func initialState() -> AppFeature.State { AppFeature.State(now: now, calendar: calendar) }

    static func signedIn() -> AppFeature.State {
        var s = initialState()
        let customer = Customer(id: "c", givenName: "Jordan", familyName: "Avery", email: EmailAddress("j@example.com")!, memberSince: now)
        s.session.phase = .signedIn(Session(customer: customer, expiresAt: now.addingTimeInterval(3600)))
        s.accounts.accounts = .loaded(AccountsOverview(accounts: accounts))
        s.transfer.recipients = .loaded(recipients)
        s.transfer.draft.sourceID = chequing.id
        s.bills.payees = .loaded([hydroPayee])
        s.bills.draft.sourceID = chequing.id
        return s
    }
}
