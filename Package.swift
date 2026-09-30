// swift-tools-version:5.9
import PackageDescription

// 計算ロジック・設定・テンプレート処理（UIに依存しない共通コード）。
// macOS / iPadOS アプリ（App/）から利用し、Linux でもテストを実行できる。
let package = Package(
    name: "InstallmentKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "InstallmentKit", targets: ["InstallmentKit"]),
    ],
    targets: [
        .target(name: "InstallmentKit", resources: [.copy("Resources/default.html")]),
        .testTarget(name: "InstallmentKitTests", dependencies: ["InstallmentKit"]),
    ]
)
