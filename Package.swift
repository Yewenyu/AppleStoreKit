// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleStoreKit",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "AppleStoreKit", targets: ["AppleStoreKit"]),
    ],
    targets: [
        .target(
            name: "AppleStoreKit",
            path: "AppleStoreKit",
            sources: ["IAPManager.swift", "StoreKit1Manager.swift", "StoreKit2Manager.swift", "RefundManager.swift", "AppleStoreKit.h"]
        ),
    ]
)
