// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "WhisperCLIPoc",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "WhisperCLIPoc", targets: ["WhisperCLIPoc"])
  ],
  dependencies: [
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
  ],
  targets: [
    .target(
      name: "WhisperCLIPocCore",
      dependencies: [
        .product(name: "WhisperKit", package: "argmax-oss-swift")
      ]
    ),
    .executableTarget(
      name: "WhisperCLIPoc",
      dependencies: ["WhisperCLIPocCore"]
    ),
  ]
)
