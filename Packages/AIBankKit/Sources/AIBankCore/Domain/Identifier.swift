import Foundation

/// A strongly typed identifier. `Identifier<Account>` can never be passed where `Identifier<Biller>` is expected.
/// Identifiers are opaque, stable strings issued by the backend (never regenerated at launch).
public struct Identifier<Tag>: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func == (l: Self, r: Self) -> Bool { l.rawValue == r.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}
