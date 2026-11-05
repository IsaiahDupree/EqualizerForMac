// swift-tools-version: 5.9
import PackageDescription

// The other Sonance apps pin this small, first-party package to a reviewed Git revision.
// It has no SDK, advertising, replay, or third-party package dependencies.
let package = Package(
    name: "SonanceAnalytics",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SonanceAnalytics", targets: ["SonanceAnalytics"]),
               .executable(name: "analytics-contract", targets: ["AnalyticsContract"])],
    targets: [
        .target(name: "SonanceAnalytics", resources: [.process("Resources")]),
        .executableTarget(name: "AnalyticsContract", dependencies: ["SonanceAnalytics"], path: "Tools/AnalyticsContract"),
        .testTarget(name: "SonanceAnalyticsTests", dependencies: ["SonanceAnalytics"],
                    path: "PackageTests/SonanceAnalyticsTests", exclude: ["Fixtures"])
    ]
)
