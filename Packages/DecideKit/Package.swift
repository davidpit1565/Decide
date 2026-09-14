// swift-tools-version: 6.0
import PackageDescription

/// DecideKit holds everything in the product that does not need UIKit or SwiftUI:
///
///   DecideCore  the decision, stability, question and memory engines
///   DecideFlow  the decision pipeline: coordinator, service contract, configuration
///
/// Keeping these out of the app target means the whole of DECIDE's reasoning can be
/// built and tested on any machine, including CI without Xcode. The app target on
/// top of it is presentation, persistence and StoreKit.
let package = Package(
    name: "DecideKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DecideCore", targets: ["DecideCore"]),
        .library(name: "DecideFlow", targets: ["DecideFlow"])
    ],
    targets: [
        .target(
            name: "DecideCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecideCoreTests",
            dependencies: ["DecideCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DecideFlow",
            dependencies: ["DecideCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecideFlowTests",
            dependencies: ["DecideFlow", "DecideCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
