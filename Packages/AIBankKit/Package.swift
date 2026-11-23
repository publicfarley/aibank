// swift-tools-version: 6.0
import PackageDescription

// AIBankCore      – pure functional core. Imports Foundation only. No I/O, no clocks, no randomness.
// AIBankBoundary  – DTOs, parsing DTO <-> domain, and the fake backend that stands in for a server.
let package = Package(
    name: "AIBankKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AIBankCore", targets: ["AIBankCore"]),
        .library(name: "AIBankBoundary", targets: ["AIBankBoundary"]),
    ],
    targets: [
        .target(name: "AIBankCore"),
        .target(name: "AIBankBoundary", dependencies: ["AIBankCore"]),
        .testTarget(name: "AIBankCoreTests", dependencies: ["AIBankCore"]),
        .testTarget(name: "AIBankBoundaryTests", dependencies: ["AIBankBoundary", "AIBankCore"]),
    ]
)
