// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UptimeKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "UptimeKit", targets: ["UptimeKit"]),
    ],
    targets: [
        .target(name: "UptimeKit"),
        .testTarget(
            name: "UptimeKitTests",
            dependencies: ["UptimeKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
