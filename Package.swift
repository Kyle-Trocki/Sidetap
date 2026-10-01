// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sidetap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SidetapCore", targets: ["SidetapCore"]),
        .executable(name: "SidetapSoak", targets: ["SidetapSoak"]),
        .executable(name: "SidetapReplay", targets: ["SidetapReplay"])
    ],
    targets: [
        .target(name: "SidetapCore", path: "Sources/SidetapCore"),
        .executableTarget(
            name: "SidetapSoak",
            dependencies: ["SidetapCore"],
            path: "Sources/SidetapSoak"
        ),
        .target(
            name: "SidetapReplaySupport",
            dependencies: ["SidetapCore"],
            path: "Sources/SidetapReplaySupport"
        ),
        .executableTarget(
            name: "SidetapReplay",
            dependencies: ["SidetapCore", "SidetapReplaySupport"],
            path: "Sources/SidetapReplay"
        ),
        .testTarget(
            name: "SidetapCoreTests",
            dependencies: ["SidetapCore"],
            path: "Tests/SidetapCoreTests"
        ),
        .testTarget(
            name: "SidetapReplayTests",
            dependencies: ["SidetapReplaySupport", "SidetapCore"],
            path: "Tests/SidetapReplayTests"
        )
    ]
)
