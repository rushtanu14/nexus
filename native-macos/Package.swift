// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalWorkflowStudioNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalWorkflowStudioCore", targets: ["LocalWorkflowStudioCore"]),
        .executable(name: "LocalWorkflowStudioNative", targets: ["LocalWorkflowStudioNative"]),
        .executable(name: "LocalWorkflowStudioNativeModelTests", targets: ["LocalWorkflowStudioNativeModelTests"])
    ],
    targets: [
        .target(
            name: "LocalWorkflowStudioCore"
        ),
        .executableTarget(
            name: "LocalWorkflowStudioNative",
            dependencies: ["LocalWorkflowStudioCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "LocalWorkflowStudioNativeModelTests",
            dependencies: ["LocalWorkflowStudioCore"],
            path: "Tests/LocalWorkflowStudioNativeModelTests"
        )
    ]
)
