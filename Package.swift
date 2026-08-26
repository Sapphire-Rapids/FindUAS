// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindUASMac",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FindUASCore", targets: ["FindUASCore"]),
        .executable(name: "FindUASMac", targets: ["FindUASMac"]),
        .executable(name: "FindUASCoreChecks", targets: ["FindUASCoreChecks"])
    ],
    targets: [
        .target(name: "FindUASCore"),
        .executableTarget(
            name: "FindUASMac",
            dependencies: ["FindUASCore"]
        ),
        .executableTarget(name: "FindUASCoreChecks", dependencies: ["FindUASCore"], path: "Checks")
    ],
    swiftLanguageModes: [.v5]
)
