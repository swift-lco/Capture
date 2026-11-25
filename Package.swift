// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "Capture",
            targets: [
                "Capture",
            ]
        ),
        .executable(
            name: "capturer",
            targets: [
                "capturer",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-lco/Media.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Terminal.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Arguments.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Methods.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "Capture",
            dependencies: [
                .product(
                    name: "Arguments",
                    package: "Arguments"
                ),
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
            ]
        ),
        .executableTarget(
            name: "capturer",
            dependencies: [
                "Capture",
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "Terminal",
                    package: "Terminal"
                ),
                .product(
                    name: "Arguments",
                    package: "Arguments"
                ),
                .product(
                    name: "Methods",
                    package: "Methods"
                ),
            ],
            path: "Sources/CaptureCLI"
        ),
    ]
)
