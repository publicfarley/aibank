import AIBankCore
import Observation

/// The imperative shell's only mutable cell. Holds the current state, runs the pure reducer on every action,
/// and hands the resulting effect *descriptions* to `Feature.perform`, which touches the world.
@MainActor
@Observable
final class Store<F: Feature> {
    private(set) var state: F.State
    @ObservationIgnored private let environment: F.Environment

    init(initial: F.State, environment: F.Environment) {
        self.state = initial
        self.environment = environment
    }

    func send(_ action: F.Action) {
        let reduced = F.reduce(state, action)
        state = reduced.state

        for effect in reduced.effects {
            Task { [environment] in
                for next in await F.perform(effect, environment) {
                    send(next)
                }
            }
        }
    }
}

typealias AppStore = Store<AppFeature>
