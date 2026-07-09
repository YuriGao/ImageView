// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageView",
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
            path: "Sources/ImageViewApp"
        ),
        .testTarget(
            name: "ImageViewCoreTests",
            dependencies: ["ImageViewCore"],
            path: "Tests/ImageViewCoreTests"
        )
    ]
)
