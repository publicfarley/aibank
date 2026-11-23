import Foundation

public enum Currency: String, Sendable, Equatable, Hashable, CaseIterable {
    case cad = "CAD"
    case usd = "USD"

    public var symbol: String { "$" }
}

/// An exact monetary amount stored as integer minor units (cents). Never a floating point number.
public struct Money: Sendable, Equatable, Hashable, Comparable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency = .cad) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func cad(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .cad) }
    public static func zero(_ currency: Currency = .cad) -> Money { Money(minorUnits: 0, currency: currency) }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }
    public var isPositive: Bool { minorUnits > 0 }
    public var magnitude: Money { Money(minorUnits: minorUnits == .min ? .max : Swift.abs(minorUnits), currency: currency) }
    public var negated: Money { Money(minorUnits: -minorUnits, currency: currency) }

    // Arithmetic is only meaningful within one currency; mixing is a programmer error.
    public static func + (l: Money, r: Money) -> Money {
        precondition(l.currency == r.currency, "Currency mismatch")
        return Money(minorUnits: l.minorUnits + r.minorUnits, currency: l.currency)
    }

    public static func - (l: Money, r: Money) -> Money {
        precondition(l.currency == r.currency, "Currency mismatch")
        return Money(minorUnits: l.minorUnits - r.minorUnits, currency: l.currency)
    }

    public static prefix func - (m: Money) -> Money { m.negated }

    public static func < (l: Money, r: Money) -> Bool {
        precondition(l.currency == r.currency, "Currency mismatch")
        return l.minorUnits < r.minorUnits
    }

    // MARK: Parsing (boundary-friendly, locale independent)

    /// Parses user or wire text such as "1,234.50", "$12", "0.5". At most two decimals, no exponent.
    public init?(string: String, currency: Currency = .cad) {
        var text = string.trimmingCharacters(in: .whitespaces)
        var negative = false
        if text.hasPrefix("-") { negative = true; text.removeFirst() }
        text = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard whole.allSatisfy(\.isASCIIDigit), fraction.allSatisfy(\.isASCIIDigit),
              !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2 else { return nil }

        let paddedFraction = fraction.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let dollars = Int64(whole.isEmpty ? "0" : whole), let cents = Int64(paddedFraction) else { return nil }
        let (scaled, overflow) = dollars.multipliedReportingOverflow(by: 100)
        guard !overflow, scaled <= Int64.max - cents else { return nil }
        let total = scaled + cents
        self.init(minorUnits: negative ? -total : total, currency: currency)
    }

    /// Plain decimal for the wire: "1234.50".
    public var decimalString: String {
        let sign = minorUnits < 0 ? "-" : ""
        let abs = minorUnits.magnitude
        let cents = abs % 100
        return "\(sign)\(abs / 100).\(cents < 10 ? "0" : "")\(cents)"
    }

    /// Human formatting: "$1,234.50", "-$20.00".
    public var formatted: String {
        let abs = minorUnits.magnitude
        let cents = abs % 100
        let dollars = Money.grouped(abs / 100)
        let sign = minorUnits < 0 ? "-" : ""
        return "\(sign)\(currency.symbol)\(dollars).\(cents < 10 ? "0" : "")\(cents)"
    }

    /// Value suitable for numeric App Intent parameters. Presentation only; never feed back into arithmetic.
    public var approximateDouble: Double { Double(minorUnits) / 100 }

    public init?(approximateDouble value: Double, currency: Currency = .cad) {
        guard value.isFinite, value.magnitude < 1e12 else { return nil }
        self.init(minorUnits: Int64((value * 100).rounded()), currency: currency)
    }

    private static func grouped(_ n: UInt64) -> String {
        let digits = String(n)
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
