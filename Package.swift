// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LatteReader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LatteReader", targets: ["LatteReader"])
    ],
    targets: [
        .executableTarget(
            name: "LatteReader",
            path: "LatteReader"
        )
    ]
)
