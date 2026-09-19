// swift-tools-version:5.5
import PackageDescription

// SwiftTerm 1.2.5, e2b431dbf73f775fb4807a33e4572ffd3dc6933a.
// Compatibility changes are documented in UPSTREAM.md.
let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v11)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [.target(name: "SwiftTerm", path: "Sources/SwiftTerm",
                      exclude: ["iOS", "Mac/README.md"],
                      resources: [.copy("LICENSE")])],
    swiftLanguageVersions: [.v5]
)
