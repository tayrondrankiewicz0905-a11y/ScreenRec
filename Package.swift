// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenRec",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ScreenRec", targets: ["ScreenRec"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenRec",
            path: "Sources/ScreenRec"
        )
    ],
    swiftLanguageModes: [.v5]
)
