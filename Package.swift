// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TobyShot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TobyShot", targets: ["TobyShot"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "TobyShot",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/Fonts")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TobyShotTests", dependencies: ["TobyShot"])
    ],
    swiftLanguageModes: [.v5]
)
