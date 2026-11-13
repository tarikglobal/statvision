// swift-tools-version: 5.9
import PackageDescription

// The app is built by Xcode. This package also makes the pure calculations
// independently testable with `swift test`, without launching a menu bar app.
let package = Package(
    name: "StatvisionMetrics",
    platforms: [.macOS(.v13)],
    products: [.library(name: "StatvisionMetrics", targets: ["StatvisionMetrics"])],
    targets: [
        .target(name: "StatvisionMetrics", path: "statvision/Metrics"),
        .testTarget(name: "StatvisionMetricsTests", dependencies: ["StatvisionMetrics"],
                    path: "statvisionTests")
    ]
)

