// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "video_pool",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        // The library name uses "-" because the package name contains "_".
        .library(name: "video-pool", targets: ["video_pool"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "video_pool",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // This plugin ships no bundled resources or required-reason
                // APIs, so no PrivacyInfo.xcprivacy is required. If that
                // changes, add the manifest here, e.g.:
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
