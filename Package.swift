// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindUAS",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FindUASCore", targets: ["FindUASCore"]),
        .executable(name: "FindUAS", targets: ["FindUASMac"]),
        .executable(name: "FindUASCoreChecks", targets: ["FindUASCoreChecks"])
    ],
    targets: [
        .target(
            name: "CDJIUSBBridge",
            publicHeadersPath: "include"
        ),
        .target(name: "FindUASCore"),
        .executableTarget(
            name: "FindUASMac",
            dependencies: ["FindUASCore", "CDJIUSBBridge"]
        ),
        .executableTarget(
            name: "FindUASCoreChecks",
            dependencies: ["FindUASCore", "CDJIUSBBridge"],
            path: "Checks"
        )
    ],
    swiftLanguageModes: [.v5]
)
