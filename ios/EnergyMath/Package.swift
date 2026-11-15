// swift-tools-version:5.9
// The app's pure calculation code plus its unit tests. The app target compiles the same
// source file directly (see ../project.yml); this package exists so the numbers can be
// tested with `swift test` from this directory, without a simulator.
import PackageDescription

let package = Package(
    name: "EnergyMath",
    targets: [
        .target(name: "EnergyMath"),
        .testTarget(name: "EnergyMathTests", dependencies: ["EnergyMath"]),
    ]
)
