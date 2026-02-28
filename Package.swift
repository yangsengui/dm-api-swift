// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "dm-api-swift",
    platforms: [
        .macOS(.v12),
        .iOS(.v14),
    ],
    products: [
        .library(name: "DmApiSwift", targets: ["DmApiSwift"]),
        .library(name: "DmApiObjC", targets: ["DmApiObjC"]),
    ],
    targets: [
        .target(
            name: "DmApiObjC",
            path: "Sources/DmApiObjC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DmApiSwift",
            dependencies: ["DmApiObjC"],
            path: "Sources/DmApiSwift"
        ),
        .testTarget(
            name: "DmApiSwiftTests",
            dependencies: ["DmApiSwift"],
            path: "Tests/DmApiSwiftTests"
        ),
    ]
)
