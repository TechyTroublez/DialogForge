// swift-tools-version:5.9
import PackageDescription

// DialogForgeCore is pure Foundation (models, generators, importers) and builds anywhere.
// The SwiftUI app target only exists on macOS.
var products: [Product] = [
    .library(name: "DialogForgeCore", targets: ["DialogForgeCore"])
]
var targets: [Target] = [
    .target(name: "DialogForgeCore"),
    .testTarget(name: "DialogForgeCoreTests", dependencies: ["DialogForgeCore"])
]

#if os(macOS)
products.append(.executable(name: "DialogForge", targets: ["DialogForge"]))
targets.append(.executableTarget(name: "DialogForge", dependencies: ["DialogForgeCore"]))
#endif

let package = Package(
    name: "DialogForge",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
