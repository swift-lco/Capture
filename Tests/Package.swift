// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "CaptureTests",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(
            name: "ctest",
            targets: [
                "CaptureTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Media.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "CaptureTestFlows",
            dependencies: [
                .product(name: "Capture", package: "Capture"),
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ]
)
