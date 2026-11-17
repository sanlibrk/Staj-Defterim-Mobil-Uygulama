// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StajDefteri",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "StajDefteriCore", targets: ["StajDefteriCore"])],
    targets: [
        .target(name: "StajDefteriCore"),
        .testTarget(name: "StajDefteriCoreTests", dependencies: ["StajDefteriCore"])
    ]
)
