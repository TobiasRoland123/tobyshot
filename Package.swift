// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TobyShot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TobyShot", targets: ["TobyShot"])],
    targets: [
        .executableTarget(name: "TobyShot"),
        .testTarget(name: "TobyShotTests", dependencies: ["TobyShot"])
    ],
    swiftLanguageModes: [.v5]
)
