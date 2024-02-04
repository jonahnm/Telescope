// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JupiterPatchfinder",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "JupiterPatchfinder",
            targets: [
                "JupiterPatchfinder",
            ]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(
            name: "SwiftMachO",
            path: "SwiftMachO"
        ),
        .package(name: "PatchfinderUtils",path: "PatchfinderUtils"),
    ],
    targets: [
        // Targets are the basic building blocks of a package.
        // A target can define a module or a test suite.
        //
        // Targets can depend on other targets in this package,
        // and on products in packages which this package depends on.
        .target(
            name: "JupiterPatchfinder",
            dependencies: [
                "SwiftMachO",
                "PatchfinderUtils",
            ],
            path: ""
        ),
    ]
)