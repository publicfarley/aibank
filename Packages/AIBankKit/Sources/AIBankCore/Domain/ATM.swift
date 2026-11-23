import Foundation

public struct Coordinate: Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine).
    public func distance(to other: Coordinate) -> Double {
        let r = 6_371_000.0
        let p1 = latitude * .pi / 180, p2 = other.latitude * .pi / 180
        let dp = (other.latitude - latitude) * .pi / 180
        let dl = (other.longitude - longitude) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

public enum ATMNetwork: String, Sendable, Equatable, Hashable, CaseIterable {
    case aiBank, partner

    public var title: String { self == .aiBank ? "aiBank" : "Partner network" }

    /// Fee for using a machine on this network.
    public var withdrawalFee: Money { self == .aiBank ? .zero() : .cad(300) }
}

public struct ATMServices: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let cashWithdrawal = ATMServices(rawValue: 1 << 0)
    public static let deposit = ATMServices(rawValue: 1 << 1)
    public static let wheelchairAccessible = ATMServices(rawValue: 1 << 2)
    public static let open24Hours = ATMServices(rawValue: 1 << 3)
    public static let driveThrough = ATMServices(rawValue: 1 << 4)

    public var labels: [String] {
        var out: [String] = []
        if contains(.cashWithdrawal) { out.append("Withdrawals") }
        if contains(.deposit) { out.append("Deposits") }
        if contains(.wheelchairAccessible) { out.append("Accessible") }
        if contains(.open24Hours) { out.append("24 hours") }
        if contains(.driveThrough) { out.append("Drive-through") }
        return out
    }
}

/// Opening hours, as minutes after local midnight, the same every day.
public struct DailyHours: Sendable, Equatable {
    public let opensAtMinute: Int
    public let closesAtMinute: Int

    public init(opensAtMinute: Int, closesAtMinute: Int) {
        self.opensAtMinute = opensAtMinute
        self.closesAtMinute = closesAtMinute
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minute >= opensAtMinute && minute < closesAtMinute
    }

    public var text: String {
        func f(_ m: Int) -> String {
            let h = m / 60, mm = m % 60
            let h12 = h % 12 == 0 ? 12 : h % 12
            return "\(h12):\(mm < 10 ? "0" : "")\(mm) \(h < 12 ? "AM" : "PM")"
        }
        return "\(f(opensAtMinute)) – \(f(closesAtMinute))"
    }
}

public struct ATM: Identifiable, Sendable, Equatable {
    public typealias ID = Identifier<ATM>

    public let id: ID
    public let name: String
    public let network: ATMNetwork
    public let address: String
    public let city: String
    public let coordinate: Coordinate
    public let services: ATMServices
    public let hours: DailyHours

    public init(id: ID, name: String, network: ATMNetwork, address: String, city: String,
                coordinate: Coordinate, services: ATMServices, hours: DailyHours) {
        self.id = id
        self.name = name
        self.network = network
        self.address = address
        self.city = city
        self.coordinate = coordinate
        self.services = services
        self.hours = hours
    }

    public func isOpen(at date: Date, calendar: Calendar) -> Bool {
        services.contains(.open24Hours) || hours.contains(date, calendar: calendar)
    }

    public var hoursText: String { services.contains(.open24Hours) ? "Open 24 hours" : hours.text }
}

public struct ATMFilter: Sendable, Equatable {
    public var requiredServices: ATMServices
    public var onlyOpenNow: Bool
    public var network: ATMNetwork?

    public init(requiredServices: ATMServices = [], onlyOpenNow: Bool = false, network: ATMNetwork? = nil) {
        self.requiredServices = requiredServices
        self.onlyOpenNow = onlyOpenNow
        self.network = network
    }

    public var isActive: Bool { !requiredServices.isEmpty || onlyOpenNow || network != nil }
}

public struct ATMResult: Identifiable, Sendable, Equatable {
    public let atm: ATM
    public let distanceMeters: Double
    public let isOpen: Bool
    public var id: ATM.ID { atm.id }

    public var distanceText: String {
        distanceMeters < 1000 ? "\(Int(distanceMeters.rounded())) m" : String(format: "%.1f km", distanceMeters / 1000)
    }
}

public enum ATMFinder {
    /// Machines matching `filter`, nearest first.
    public static func nearby(_ atms: [ATM], to origin: Coordinate, filter: ATMFilter, now: Date,
                              calendar: Calendar) -> [ATMResult] {
        atms.compactMap { atm -> ATMResult? in
            if !atm.services.isSuperset(of: filter.requiredServices) { return nil }
            if let network = filter.network, atm.network != network { return nil }
            let open = atm.isOpen(at: now, calendar: calendar)
            if filter.onlyOpenNow && !open { return nil }
            return ATMResult(atm: atm, distanceMeters: origin.distance(to: atm.coordinate), isOpen: open)
        }
        .sorted { ($0.distanceMeters, $0.atm.id.rawValue) < ($1.distanceMeters, $1.atm.id.rawValue) }
    }
}
