// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageView",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ImageViewCore", targets: ["ImageViewCore"]),
        .executable(name: "ImageView", targets: ["ImageViewApp"])
    ],
    targets: [
        .target(
            name: "ImageViewCore",
            path: "Sources/ImageViewCore"
        ),
        .executableTarget(
            name: "ImageViewApp",
            dependencies: ["ImageViewCore"],
            path: "Sources/ImageViewApp",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ]
        ),
        .testTarget(
            name: "ImageViewCoreTests",
            dependencies: ["ImageViewCore"],
            path: "Tests/ImageViewCoreTests"
        ),
        .testTarget(
            name: "ImageViewAppTests",
            dependencies: ["ImageViewApp", "ImageViewCore"],
            path: "Tests/ImageViewAppTests"
        )
    ]
)
