// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DaemonNative",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DaemonKit", targets: ["DaemonKit"]),
        .library(name: "DaemonIOS", targets: ["DaemonIOS"]),
        .executable(name: "DaemonMac", targets: ["DaemonMac"]),
        .executable(name: "DaemonBridgeChecks", targets: ["DaemonBridgeChecks"]),
    ],
    targets: [
        .target(
            name: "DaemonNativeCore",
            path: ".",
            exclude: [
                "AGENTS.md", "README.md", "Makefile", "CMakeLists.txt",
                "build.ps1", "run.ps1", "run.sh", "docs", "examples",
                "experimental", "prototypes", "tests", "package",
                "src/api", "src/core", "src/library", "scripts",
                "apple/DaemonKit", "apple/DaemonKitTests", "apple/DaemonMac",
                "apple/DaemonIOS", "apple/DaemonIOSApp",
                "apple/BridgeChecks",
            ],
            sources: [
                "src/daemon/policy.cpp", "src/daemon/trace.cpp",
                "src/daemon/json.cpp", "src/daemon/bridge.cpp",
                "adapters/git_adapter.cpp",
                "adapters/posix_process.cpp",
            ],
            publicHeadersPath: "apple/CoreHeaders",
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("adapters"),
                .define("DAEMON_PLATFORM_IOS", to: "1", .when(platforms: [.iOS])),
            ]
        ),
        .target(name: "DaemonKit", dependencies: ["DaemonNativeCore"], path: "apple/DaemonKit"),
        .executableTarget(
            name: "DaemonMac", dependencies: ["DaemonKit"], path: "apple/DaemonMac",
            exclude: ["Info.plist", "Assets"]
        ),
        .target(name: "DaemonIOS", dependencies: ["DaemonKit"], path: "apple/DaemonIOS"),
        .executableTarget(name: "DaemonBridgeChecks", dependencies: ["DaemonKit"], path: "apple/BridgeChecks"),
        .testTarget(name: "DaemonKitTests", dependencies: ["DaemonKit"], path: "apple/DaemonKitTests"),
    ],
    cxxLanguageStandard: .cxx20
)
