// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "crap4swift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "crap4swift", targets: ["crap4swift"]),
        .library(name: "Crap4SwiftCore", targets: ["Crap4SwiftCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "603.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "crap4swift",
            dependencies: ["Crap4SwiftCore"]
        ),
        .target(
            name: "Crap4SwiftCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Crap4SwiftCoreTests",
            dependencies: ["Crap4SwiftCore"]
        ),
    ]
)
