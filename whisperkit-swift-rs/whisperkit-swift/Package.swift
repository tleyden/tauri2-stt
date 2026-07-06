// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "whisperkit-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "whisperkit-swift",
            type: .static,
            targets: ["whisperkit-swift"]
        ),
    ],
    dependencies: [
        .package(name: "SwiftRs", url: "https://github.com/Brendonovich/swift-rs", from: "1.0.6"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "whisperkit-swift",
            dependencies: [
                .product(name: "SwiftRs", package: "SwiftRs"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
    ]
)
