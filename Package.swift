// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodeXCode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeCodeXCode", targets: ["ClaudeCodeXCode"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCodeXCode",
            dependencies: [
                "SwiftTerm",
                "HotKey"
            ],
            path: "Sources/ClaudeCodeXCode"
        )
    ]
)
