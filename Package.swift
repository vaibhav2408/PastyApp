// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clip20",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clip20", targets: ["Clip20"])],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "Clip20", dependencies: ["ClipboardCore"], resources: [.copy("Resources/Fonts")]),
        .executableTarget(name: "Clip20Checks", dependencies: ["ClipboardCore"], path: "Tests/ClipboardCoreTests"),
    ]
)
