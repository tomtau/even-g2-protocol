// swift-tools-version:5.9
// Even G2 Protocol Swift Examples

import PackageDescription

let package = Package(
    name: "EvenG2Examples",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "notification", targets: ["Notification"]),
        .executable(name: "teleprompter", targets: ["Teleprompter"]),
        .executable(name: "even-ai", targets: ["EvenAI"]),
        .executable(name: "gesture", targets: ["Gesture"]),
        .executable(name: "navigation", targets: ["Navigation"]),
        .executable(name: "translation", targets: ["Translation"]),
    ],
    targets: [
        .target(
            name: "Shared",
            dependencies: []
        ),
        .executableTarget(
            name: "Notification",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "Teleprompter",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "EvenAI",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "Gesture",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "Navigation",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "Translation",
            dependencies: ["Shared"]
        ),
    ]
)
