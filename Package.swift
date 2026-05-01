// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kubera",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Kubera",
            path: "Kubera",
            exclude: ["Info.plist", "Kubera.entitlements"],
            resources: [.copy("Assets.xcassets")]
        ),
    ]
)
