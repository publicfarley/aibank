import Foundation

public struct ATMState: Equatable, Sendable {
    /// King St & Bay St, Toronto. The shell replaces this with the device location when it has one.
    public static let defaultLocation = Coordinate(latitude: 43.6487, longitude: -79.3815)

    public var atms: LoadState<[ATM]> = .idle
    public var userLocation: Coordinate = ATMState.defaultLocation
    public var filter = ATMFilter()
    public var selectedID: ATM.ID?
    public var now: Date
    public var calendar: Calendar

    public init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    /// Derived, pure: what the list and map show right now.
    public var results: [ATMResult] {
        ATMFinder.nearby(atms.value ?? [], to: userLocation, filter: filter, now: now, calendar: calendar)
    }

    public var selected: ATMResult? { results.first { $0.id == selectedID } }
}

public enum ATMAction: Sendable {
    case appeared(now: Date)
    case loaded(Result<[ATM], BankError>)
    case locationUpdated(Coordinate)
    case filterChanged(ATMFilter)
    case selected(ATM.ID?)
    case clockTicked(Date)

    var failure: BankError? {
        if case .loaded(.failure(let e)) = self { e } else { nil }
    }
}

enum ATMFeature {
    static func reduce(_ state: ATMState, _ action: ATMAction) -> Reduced<ATMState, BankEffect> {
        var s = state
        switch action {
        case .appeared(let now):
            s.now = now
            if s.atms.value == nil { s.atms = .loading }
            return Reduced(s, [.loadATMs])
        case .loaded(.success(let atms)):
            s.atms = .loaded(atms)
            return Reduced(s)
        case .loaded(.failure(let error)):
            if s.atms.value == nil { s.atms = .failed(error) }
            return Reduced(s)
        case .locationUpdated(let coordinate):
            s.userLocation = coordinate
            return Reduced(s)
        case .filterChanged(let filter):
            s.filter = filter
            // A selection that the new filter hides would be a ghost; drop it.
            if let id = s.selectedID, !s.results.contains(where: { $0.id == id }) { s.selectedID = nil }
            return Reduced(s)
        case .selected(let id):
            s.selectedID = id
            return Reduced(s)
        case .clockTicked(let now):
            s.now = now
            return Reduced(s)
        }
    }
}
