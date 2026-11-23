import Foundation

/// The fake bank's starting data. Identifiers are fixed strings so they are stable across launches and devices;
/// only the dates move, relative to the moment the data is first created.
enum SeedData {
    /// Demo sign-in. Shown on the sign-in screen so anyone can try the app.
    static let demoCard = "4500123456789010"
    static let demoPassword = "aibank1"

    static func make(now: Date) -> ServerStore {
        func ago(days: Double, hour: Double = 0) -> String {
            Wire.string(now.addingTimeInterval(-(days * 86_400) - hour * 3_600))
        }

        let customer = CustomerDTO(id: "cust-001", givenName: "Jordan", familyName: "Avery",
                                   email: "jordan.avery@example.com", memberSince: ago(days: 2_900))

        let accounts: [AccountDTO] = [
            AccountDTO(id: "acct-chq-001", kind: "chequing", nickname: "Everyday Chequing", number: "5012348801",
                       currency: "CAD", balance: "4823.67", borrowingLimit: "500.00", interestRateBasisPoints: 0),
            AccountDTO(id: "acct-sav-001", kind: "savings", nickname: "Rainy Day Savings", number: "5012348902",
                       currency: "CAD", balance: "8450.12", borrowingLimit: "0.00", interestRateBasisPoints: 400),
            AccountDTO(id: "acct-tfsa-001", kind: "tfsa", nickname: "TFSA", number: "6098117703",
                       currency: "CAD", balance: "21300.00", borrowingLimit: "0.00", interestRateBasisPoints: 350),
            AccountDTO(id: "acct-cc-001", kind: "creditCard", nickname: "Visa Infinite", number: "4500123456789010",
                       currency: "CAD", balance: "-1246.38", borrowingLimit: "10000.00", interestRateBasisPoints: 1999),
            AccountDTO(id: "acct-loc-001", kind: "lineOfCredit", nickname: "Home Equity Line", number: "7731002244",
                       currency: "CAD", balance: "-12500.00", borrowingLimit: "50000.00", interestRateBasisPoints: 720),
        ]

        var n = 0
        func tx(_ acct: String, _ kind: String, _ amount: String, _ days: Double, _ hour: Double, _ title: String,
                _ category: String, detail: String? = nil, pending: Bool = false) -> TransactionDTO {
            n += 1
            return TransactionDTO(id: "txn-seed-\(String(format: "%03d", n))", accountId: acct, kind: kind, amount: amount,
                                  currency: "CAD", date: ago(days: days, hour: hour), status: pending ? "pending" : "posted",
                                  title: title, detail: detail, category: category)
        }

        let chq = "acct-chq-001", sav = "acct-sav-001", cc = "acct-cc-001", tfsa = "acct-tfsa-001"
        let transactions: [TransactionDTO] = [
            tx(chq, "purchase", "-6.45", 0, 3, "Daily Grind Coffee", "dining", pending: true),
            tx(chq, "purchase", "-58.12", 1, 5, "Greenfield Market", "groceries", detail: "Debit purchase"),
            tx(chq, "billPayment", "-92.40", 2, 2, "Toronto Hydro", "utilities", detail: "Bill payment"),
            tx(chq, "payroll", "2150.00", 3, 6, "Northwind Ltd. Payroll", "income", detail: "Direct deposit"),
            tx(chq, "atmWithdrawal", "-80.00", 4, 8, "ATM Withdrawal", "cash", detail: "King & Bay"),
            tx(chq, "eTransferReceived", "45.00", 5, 4, "e-Transfer from Sam Patel", "transfers", detail: "Dinner split"),
            tx(chq, "purchase", "-34.99", 6, 2, "Streamline Video", "entertainment", detail: "Monthly subscription"),
            tx(chq, "purchase", "-23.75", 7, 7, "Metro Transit", "transport"),
            tx(chq, "eTransferSent", "-120.00", 9, 1, "e-Transfer to Morgan Lee", "transfers", detail: "Concert tickets"),
            tx(chq, "billPayment", "-79.00", 10, 3, "Maple Mobile", "utilities", detail: "Bill payment"),
            tx(chq, "purchase", "-142.88", 11, 4, "Greenfield Market", "groceries"),
            tx(chq, "fee", "-4.00", 12, 0, "Monthly account fee", "fees"),
            tx(chq, "payroll", "2150.00", 17, 6, "Northwind Ltd. Payroll", "income", detail: "Direct deposit"),
            tx(chq, "purchase", "-61.30", 18, 5, "Harbour Grill", "dining"),
            tx(chq, "billPayment", "-1650.00", 20, 2, "Harbourfront Condo Fees", "housing", detail: "Bill payment"),
            tx(chq, "purchase", "-48.20", 22, 6, "Pharmasave", "health"),

            tx(sav, "deposit", "500.00", 3, 4, "Transfer from Chequing", "transfers"),
            tx(sav, "interest", "27.84", 12, 0, "Interest earned", "fees"),
            tx(sav, "deposit", "500.00", 17, 4, "Transfer from Chequing", "transfers"),

            tx(tfsa, "deposit", "300.00", 15, 3, "Contribution", "transfers"),
            tx(tfsa, "interest", "62.10", 12, 0, "Interest earned", "fees"),

            tx(cc, "purchase", "-212.45", 1, 7, "Skyline Electronics", "shopping"),
            tx(cc, "purchase", "-86.20", 3, 3, "Bluebird Bistro", "dining"),
            tx(cc, "purchase", "-45.00", 4, 2, "Northern Fuel", "transport"),
            tx(cc, "purchase", "-129.99", 8, 5, "Trailhead Outfitters", "shopping"),
            tx(cc, "refund", "39.00", 9, 6, "Refund: Trailhead Outfitters", "shopping"),
            tx(cc, "purchase", "-17.80", 10, 1, "Daily Grind Coffee", "dining"),
        ]

        let recipients: [RecipientDTO] = [
            RecipientDTO(id: "rcpt-001", name: "Sam Patel", email: "sam.patel@example.com", autodeposit: true),
            RecipientDTO(id: "rcpt-002", name: "Morgan Lee", email: "morgan.lee@example.com", autodeposit: false),
            RecipientDTO(id: "rcpt-003", name: "Taylor Nguyen", email: "taylor.nguyen@example.com", autodeposit: true),
            RecipientDTO(id: "rcpt-004", name: "Riley O'Connor", email: "riley.oconnor@example.com", autodeposit: false),
        ]

        let hydro = BillerDTO(id: "biller-hydro", name: "Toronto Hydro", category: "utilities", minAccountLength: 10, maxAccountLength: 10)
        let mobile = BillerDTO(id: "biller-mobile", name: "Maple Mobile", category: "telecom", minAccountLength: 9, maxAccountLength: 10)
        let gas = BillerDTO(id: "biller-gas", name: "CityGas", category: "utilities", minAccountLength: 8, maxAccountLength: 12)
        let insurance = BillerDTO(id: "biller-insure", name: "Shield Insurance", category: "insurance", minAccountLength: 8, maxAccountLength: 10)
        let condo = BillerDTO(id: "biller-condo", name: "Harbourfront Condo Fees", category: "housing", minAccountLength: 6, maxAccountLength: 8)
        let tax = BillerDTO(id: "biller-tax", name: "Lakeshore Property Tax", category: "tax", minAccountLength: 12, maxAccountLength: 12)

        let payees: [PayeeDTO] = [
            PayeeDTO(id: "payee-001", biller: hydro, accountNumber: "4400128891", nickname: nil, lastPayment: "92.40"),
            PayeeDTO(id: "payee-002", biller: mobile, accountNumber: "5503019921", nickname: "Phone", lastPayment: "79.00"),
            PayeeDTO(id: "payee-003", biller: gas, accountNumber: "88120047", nickname: nil, lastPayment: "64.15"),
            PayeeDTO(id: "payee-004", biller: insurance, accountNumber: "20481177", nickname: "Car insurance", lastPayment: "139.00"),
            PayeeDTO(id: "payee-005", biller: condo, accountNumber: "774120", nickname: "Condo", lastPayment: "1650.00"),
            PayeeDTO(id: "payee-006", biller: tax, accountNumber: "301122004455", nickname: nil, lastPayment: nil),
        ]

        func atm(_ id: String, _ name: String, _ network: String, _ address: String, _ lat: Double, _ lon: Double,
                 _ services: [String], _ opens: Int = 6 * 60, _ closes: Int = 22 * 60) -> ATMDTO {
            ATMDTO(id: id, name: name, network: network, address: address, city: "Toronto", latitude: lat, longitude: lon,
                   services: services, opensAtMinute: opens, closesAtMinute: closes)
        }
        let full = ["withdrawal", "deposit", "accessible"]
        let atms: [ATMDTO] = [
            atm("atm-001", "aiBank King & Bay", "aiBank", "100 King St W", 43.6487, -79.3815, full + ["24h"]),
            atm("atm-002", "Union Station Concourse", "aiBank", "65 Front St W", 43.6453, -79.3806, full + ["24h"]),
            atm("atm-003", "Eaton Centre Level 1", "aiBank", "220 Yonge St", 43.6544, -79.3807, ["withdrawal", "deposit"], 10 * 60, 21 * 60),
            atm("atm-004", "St. Lawrence Market", "partner", "92 Front St E", 43.6487, -79.3715, ["withdrawal", "accessible"], 8 * 60, 18 * 60),
            atm("atm-005", "Queen & Spadina", "partner", "401 Queen St W", 43.6489, -79.3954, ["withdrawal"], 0, 24 * 60),
            atm("atm-006", "Harbourfront Centre", "aiBank", "235 Queens Quay W", 43.6389, -79.3817, full, 7 * 60, 23 * 60),
            atm("atm-007", "Yonge-Dundas Square", "partner", "1 Dundas St E", 43.6561, -79.3802, ["withdrawal", "24h"]),
            atm("atm-008", "University & College", "aiBank", "480 University Ave", 43.6595, -79.3883, full, 6 * 60, 22 * 60),
            atm("atm-009", "Roundhouse Park", "partner", "255 Bremner Blvd", 43.6426, -79.3871, ["withdrawal", "accessible"], 9 * 60, 20 * 60),
            atm("atm-010", "Distillery District", "aiBank", "55 Mill St", 43.6503, -79.3596, full + ["drivethrough"], 6 * 60, 23 * 60),
        ]

        return ServerStore(customer: customer, accounts: accounts, transactions: transactions, recipients: recipients,
                           payees: payees, atms: atms, session: nil, confirmationCounter: 100_000)
    }
}
