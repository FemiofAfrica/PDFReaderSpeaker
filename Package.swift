// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LatteReader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LatteReader", targets: ["LatteReader"]),
        .executable(name: "PagePrompt", targets: ["PagePrompt"]),
    ],
    targets: [
        .target(
            name: "PagePromptSupport",
            path: "PagePromptSupport"
        ),
        .executableTarget(
            name: "LatteReader",
            dependencies: ["PagePromptSupport"],
            path: "LatteReader"
        ),
        .executableTarget(
            name: "PagePrompt",
            path: "PagePrompt"
        ),
        .testTarget(
            name: "PagePromptSupportTests",
            dependencies: ["PagePromptSupport"],
            path: "Tests/PagePromptSupportTests"
        ),
    ]
)
