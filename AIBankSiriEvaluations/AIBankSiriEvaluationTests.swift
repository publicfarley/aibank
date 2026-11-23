import SiriEvaluations
import Testing

// Drives real Siri on a physical device (iOS 27.3+). Before a run: install and launch aiBank once,
// and sign in to aiBank (demo card) so the 30-minute session is live. A signed-out run stalls on the sign-in hand-off.
struct AIBankEvaluation: Evaluation {
    let name: String
    let dataset: SiriScenarioLoader

    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await SiriService.run(scenario: sample)
    }

    var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}

@Suite("aiBank - Siri", .serialized)
struct AIBankSiriEvaluationTests {
    static let appDefinitions = IntentDefinitions(bundleIdentifier: "com.example.aibank")
    static let GetAccountsIntent = appDefinitions.intents["GetAccountsIntent"]
    static let SendETransferIntent = appDefinitions.intents["SendETransferIntent"]
    static let PayBillIntent = appDefinitions.intents["PayBillIntent"]
    static let RecipientEntity = appDefinitions.entities["RecipientEntity"]
    static let PayeeEntity = appDefinitions.entities["PayeeEntity"]
    static let AccountEntity = appDefinitions.entities["AccountEntity"]
    static let SendETransferSkill = appDefinitions.skills["send-etransfer"]
    static let PayBillSkill = appDefinitions.skills["pay-bill"]
    static let AccountQuestionsSkill = appDefinitions.skills["account-questions"]

    // MARK: - Money-moving requests reach the money-moving tool (regression: they stopped at the balances answer)

    // A call that stops at its "Send?" confirmation isn't graded as called, so each scenario ends with "Yes".
    // That moves money in the on-device fake bank ($25 and $42.50 a run); nothing leaves the device.

    // The reported bug, as said. Chequing and savings can both cover $25, so the skill asks which account;
    // the second turn answers. The send may happen on either turn, so it is checked across the scenario.
    static let sendSamAsSaid = SiriScenario {
        UserTurn("Send $25 to Sam with aiBank") {
            Loads(.required) { SendETransferSkill }
        }
        UserTurn("From Everyday Chequing")
        UserTurn("Yes")
    } expectation: {
        Calls {
            GetAccountsIntent
            SendETransferIntent.expect(
                recipient: RecipientEntity.expectIdentifier("rcpt-001"),
                amount: .matches(#Predicate<Double> { $0 == 25 }, requirement: "25 dollars")
            )
        }
        Calls(.disallowed) { PayBillIntent }
    }

    static let sendSamFromChequing = SiriScenario {
        UserTurn("In aiBank, send Sam $25 from Everyday Chequing") {
            Loads(.required) { SendETransferSkill }
        }
        UserTurn("Yes")
    } expectation: {
        Calls {
            GetAccountsIntent
            SendETransferIntent.expect(
                recipient: RecipientEntity.expectIdentifier("rcpt-001"),
                amount: .matches(#Predicate<Double> { $0 == 25 }, requirement: "25 dollars"),
                fromAccount: AccountEntity.expectIdentifier("acct-chq-001")
            )
        }
        Calls(.disallowed) { PayBillIntent }
    }

    static let payPhoneBill = SiriScenario {
        UserTurn("In aiBank, pay my Phone bill $42.50 from Everyday Chequing") {
            Loads(.required) { PayBillSkill }
        }
        // Siri's confirmation question for Pay Bill reliably arrives one turn late on device, so the first "Yes"
        // lands before it; the second answers it.
        UserTurn("Yes")
        UserTurn("Yes")
    } expectation: {
        Calls {
            GetAccountsIntent
            PayBillIntent.expect(
                payee: PayeeEntity.expectIdentifier("payee-002"),
                amount: .matches(#Predicate<Double> { $0 == 42.5 }, requirement: "42.50 dollars"),
                fromAccount: AccountEntity.expectIdentifier("acct-chq-001")
            )
        }
        Calls(.disallowed) { SendETransferIntent }
    }

    static let moneyMoving = AIBankEvaluation(
        name: "aiBank - Payments reach the payment tool",
        dataset: SiriScenarioLoader { sendSamAsSaid; sendSamFromChequing; payPhoneBill }
    )

    @Test("Siri carries e-Transfer and bill requests through to the payment tool", .evaluates(moneyMoving))
    func paymentsReachPaymentTool() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
    }

    // MARK: - Balance questions still use Get Accounts and never move money

    static let chequingBalance = SiriScenario {
        UserTurn("What's my chequing balance in aiBank?") {
            Loads(.required) { AccountQuestionsSkill }
            Calls { GetAccountsIntent }
            Calls(.disallowed) { SendETransferIntent; PayBillIntent }
        }
    }

    static let balances = AIBankEvaluation(
        name: "aiBank - Balance questions",
        dataset: SiriScenarioLoader { chequingBalance }
    )

    @Test("Siri answers balance questions with Get Accounts", .evaluates(balances))
    func balanceQuestions() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
    }

    // MARK: - Each App Skill loads for its task (single turns: nothing is confirmed, so no money moves)

    static let sendSkill = SiriScenario {
        UserTurn("In aiBank, send Sam $25 from Everyday Chequing") { Loads(.required) { SendETransferSkill } }
    }

    static let payBillSkill = SiriScenario {
        UserTurn("In aiBank, pay my Phone bill $42.50 from Everyday Chequing") { Loads(.required) { PayBillSkill } }
    }

    static let skillsEvaluation = AIBankEvaluation(
        name: "aiBank - App Skills",
        dataset: SiriScenarioLoader { sendSkill; payBillSkill; chequingBalance }
    )

    @Test("Siri loads aiBank's App Skills", .evaluates(skillsEvaluation))
    func loadsSkills() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1.0)
    }
}
