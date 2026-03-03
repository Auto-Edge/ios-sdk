// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutoEdgeSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AutoEdgeSDK",
            targets: ["AutoEdgeSDK"]
        ),
    ],
    targets: [
        .target(
            name: "AutoEdgeSDK",
            dependencies: [],
            path: "Sources/AutoEdgeSDK"
        ),
        .testTarget(
            name: "AutoEdgeSDKTests",
            dependencies: ["AutoEdgeSDK"],
            path: "Tests/AutoEdgeSDKTests"
        ),
    ]
)
