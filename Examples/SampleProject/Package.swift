// swift-tools-version:5.9
import PackageDescription

// A deliberately uneven package: one well-tested function, one untested
// branchy one. Run `crap4swift Examples/SampleProject` to see the difference.
let package = Package(
    name: "SampleLib",
    targets: [
        .target(name: "SampleLib"),
        .testTarget(name: "SampleLibTests", dependencies: ["SampleLib"]),
    ]
)
