// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DecideCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DecideCore", targets: ["DecideCore"])
    ],
    targets: [
        .target(
            name: "DecideCore",
            path: "Sources/DecideCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecideCoreTests",
            dependencies: ["DecideCore"],
            path: "Tests/DecideCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
