// swift-tools-version: 6.0
import PackageDescription
import Foundation

/// Ezypick's domain and business rules, packaged so they can be built and tested without an app
/// target. The iOS app depends on this package; Swift Package Manager is the mechanism taught in
/// Week 7.
///
/// Xcode bundles Swift Testing, so no dependency is needed to run these tests there. The
/// Command Line Tools toolchain does not, so setting EZYPICK_STANDALONE_TESTING=1 pulls
/// swift-testing in for a terminal run:
///
///     EZYPICK_STANDALONE_TESTING=1 swift test
let standalone = ProcessInfo.processInfo.environment["EZYPICK_STANDALONE_TESTING"] != nil

let package = Package(
    name: "EzypickCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EzypickCore", targets: ["EzypickCore"])
    ],
    dependencies: standalone
        ? [.package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0")]
        : [],
    targets: [
        .target(name: "EzypickCore", resources: [.process("Resources")]),
        .testTarget(
            name: "EzypickCoreTests",
            dependencies: standalone
                ? ["EzypickCore", .product(name: "Testing", package: "swift-testing")]
                : ["EzypickCore"]
        )
    ]
)
