import Foundation

/// Every rule a draft broke, reported together so the form can show them all at once.
public struct ValidationFailure<Issue: Sendable & Equatable>: Error, Sendable, Equatable {
    public let issues: [Issue]
    public init(_ issues: [Issue]) { self.issues = issues }
}
