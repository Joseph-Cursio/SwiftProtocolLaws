// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftProtocolLaws",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ProtocolLawKit",
            targets: ["ProtocolLawKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ProtocolLawKit",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),
        .testTarget(
            name: "ProtocolLawKitTests",
            dependencies: [
                "ProtocolLawKit",
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        )
    ]
)
