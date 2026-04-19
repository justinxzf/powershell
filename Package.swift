// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerShell",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PowerShell", targets: ["PowerShell"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "PowerShell",
            dependencies: ["SwiftTerm"],
            path: "Sources/PowerShell",
            exclude: [
                "Resources/AppIcon-master.png",
                "Resources/AppIcon.iconset"
            ],
            resources: [
                .process("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "PowerShellTests",
            dependencies: ["PowerShell"],
            path: "Tests/PowerShellTests"
        )
    ]
)
