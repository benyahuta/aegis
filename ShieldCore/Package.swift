// swift-tools-version: 6.0
// ShieldCore: the shared logic for Family Shield (SPEC §2 C1, §3).
// Zero dependencies (H4). Apple frameworks only.

import PackageDescription

let package = Package(
    name: "ShieldCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ShieldCore", targets: ["ShieldCore"]),
        .library(name: "ShieldUI", targets: ["ShieldUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ShieldCore",
            path: "Sources/ShieldCore",
            resources: [
                // Bundled SOFA snapshot, the FeedStore's last resort (§3, §5.2).
                .copy("Version/snapshot"),
                // Check catalog (§5.1) and every compiled string (§6, §7, §11).
                .copy("Catalog/catalog.json"),
                .process("Catalog/Strings/Localizable.xcstrings"),
            ]
        ),
        .target(
            name: "ShieldUI",
            dependencies: ["ShieldCore"],
            path: "Sources/ShieldUI"
        ),
        .testTarget(
            name: "ShieldCoreTests",
            dependencies: ["ShieldCore"],
            path: "Tests",
            exclude: ["ShieldUITests"],
            sources: ["ShieldCoreTests"],
            // Captured fixtures (SOFA feeds, scam corpus) live in Tests/Fixtures (§3).
            // Load them with Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures").
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ShieldUITests",
            dependencies: ["ShieldUI", "ShieldCore"],
            path: "Tests/ShieldUITests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
