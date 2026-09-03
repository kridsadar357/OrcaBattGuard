// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrcaBatteryGuardian",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OrcaBatteryGuardian", targets: ["OrcaBatteryGuardianApp"]),
        .library(name: "OrcaBatteryGuardianCore", targets: ["OrcaBatteryGuardian"])
    ],
    targets: [
        .target(
            name: "OrcaBatteryGuardian",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "OrcaBatteryGuardianApp",
            dependencies: ["OrcaBatteryGuardian"]
        ),
        .testTarget(
            name: "OrcaBatteryGuardianTests",
            dependencies: ["OrcaBatteryGuardian"]
        )
    ]
)
