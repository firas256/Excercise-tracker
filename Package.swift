// swift-tools-version:5.9
// Swift package for the platform-independent motion-processing core (Shared/).
// The iOS and watchOS apps compile these same files directly; this package exists so the
// algorithms can be unit-tested with `swift test` on macOS or Linux without a device.
import PackageDescription

let package = Package(
    name: "ExerciseCore",
    platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "ExerciseCore", targets: ["ExerciseCore"]),
    ],
    targets: [
        .target(name: "ExerciseCore", path: "Shared"),
        .testTarget(name: "ExerciseCoreTests", dependencies: ["ExerciseCore"], path: "Tests/ExerciseCoreTests"),
    ]
)
