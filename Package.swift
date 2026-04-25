// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "cmux_iOS",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "cmux_iOS",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .testTarget(
            name: "cmux_iOSTests",
            dependencies: ["cmux_iOS"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
