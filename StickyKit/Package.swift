// swift-tools-version:5.9
import PackageDescription

// Everything that isn't a screen: the provider, the lists, the guide, matching. Tested with `swift test`.
let package = Package(
    name: "StickyKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "StickyKit", targets: ["StickyKit"])],
    targets: [
        .target(name: "StickyKit"),
        .testTarget(name: "StickyKitTests", dependencies: ["StickyKit"]),
    ]
)
