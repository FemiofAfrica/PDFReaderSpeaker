// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFReaderSpeaker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PDFReaderSpeaker", targets: ["PDFReaderSpeaker"])
    ],
    targets: [
        .executableTarget(
            name: "PDFReaderSpeaker",
            path: "PDFReaderSpeaker"
        )
    ]
)
