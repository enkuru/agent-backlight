// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentBacklight",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentBacklightCore"),
        .executableTarget(name: "AgentBacklight", dependencies: ["AgentBacklightCore"]),
        .executableTarget(name: "agent-backlight-hook", dependencies: ["AgentBacklightCore"]),
        .testTarget(name: "AgentBacklightCoreTests", dependencies: ["AgentBacklightCore"])
    ]
)
