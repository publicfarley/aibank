import AIBankCore
import Foundation
import Testing
@testable import AIBank

@Suite struct EntityMappingTests {
    let account = Account(id: "acct-1", kind: .creditCard, nickname: "Visa", number: AccountNumber("4500123456789010")!,
                          balance: .cad(-123_456), borrowingLimit: .cad(1_000_000))

    @Test func accountEntityCarriesIdentityAndDollars() {
        let entity = AccountEntity(account)
        #expect(entity.id == "acct-1")
        #expect(entity.name == "Visa")
        #expect(entity.kind == .creditCard)
        #expect(entity.balance == -1234.56)
        #expect(entity.availableFunds == 8765.44)
        #expect(entity.last4 == "9010")
    }

    @Test func bankErrorsSpeakToSiri() {
        #expect(String(localized: BankError.insufficientFunds.localizedStringResource) == BankError.insufficientFunds.message)
    }

    @Test func sectionsMapToTabs() {
        for section in [AppSection.accounts, .interac, .bills, .atms] {
            #expect(section.tab.rawValue == section.rawValue)
        }
    }

    @Test func doublesRoundTripToExactMoney() {
        #expect(Money(approximateDouble: 25.5) == .cad(2_550))
        #expect(Money(approximateDouble: 0.1 + 0.2) == .cad(30))
        #expect(Money(approximateDouble: .infinity) == nil)
    }
}
