// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WishwellStorage",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "WishwellStorage", targets: ["WishwellStorage"])],
    targets: [
        .target(name: "WishwellStorage", path: "Sources", exclude: ["API.swift", "Account.swift", "Community.swift", "Wishlists.swift", "WishwellApp.swift", "SocialViews.swift"], sources: ["Models.swift", "SocialModels.swift", "SocialService.swift", "CloudSocialDatabase.swift"]),
        .testTarget(name: "WishwellStorageTests", dependencies: ["WishwellStorage"], path: "StorageTests")
    ]
)
