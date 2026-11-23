import Foundation

/// The result of a pure reduction: the next state plus *descriptions* of work for the shell to do.
public struct Reduced<State: Sendable, Effect: Sendable>: Sendable {
    public let state: State
    public let effects: [Effect]

    public init(_ state: State, _ effects: [Effect] = []) {
        self.state = state
        self.effects = effects
    }
}

extension Reduced: Equatable where State: Equatable, Effect: Equatable {}

public protocol Feature: Sendable {
    associatedtype State: Equatable & Sendable
    associatedtype Action: Sendable
    associatedtype Effect: Sendable
    associatedtype Environment: Sendable

    /// PURE. Same state + action in, same result out. No I/O, `Date()`, `UUID()`, randomness or async.
    static func reduce(_ state: State, _ action: Action) -> Reduced<State, Effect>

    /// IMPURE. The only place the program touches the world. Returns actions to feed back into `reduce`.
    static func perform(_ effect: Effect, _ env: Environment) async -> [Action]
}

/// Network-style loading lifecycle for a piece of remote data.
public enum LoadState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(BankError)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var error: BankError? {
        if case .failed(let e) = self { return e }
        return nil
    }
}
