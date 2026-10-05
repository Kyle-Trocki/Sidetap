// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sidetap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SidetapCore", targets: ["SidetapCore"]),
        .executable(name: "SidetapSoak", targets: ["SidetapSoak"])
    ],
    targets: [
        .target(name: "SidetapCore", path: "Sources/SidetapCore"),
        .executableTarget(
            name: "SidetapSoak",
            dependencies: ["SidetapCore"],
            path: "Sources/SidetapSoak"
        ),
        .testTarget(
            name: "SidetapCoreTests",
            dependencies: ["SidetapCore"],
            path: "Tests/SidetapCoreTests"
        )
    ]
)
