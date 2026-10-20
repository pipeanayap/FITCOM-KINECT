// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kinect",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Kinect",
            targets: ["Kinect"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.4"),
    ],
    targets: [
        .target(
            name: "Kinect",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
    ]
)
