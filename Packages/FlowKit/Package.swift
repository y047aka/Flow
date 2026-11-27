// swift-tools-version: 6.0
import PackageDescription

// FlowKit は 2 層構成:
// - FlowCore  : プラットフォーム非依存（Foundation のみ）。グルーピング・カタログ・現像レシピ・パイプライン。
//               将来 Windows/Linux へ移植する際もそのまま再利用する想定。
// - FlowApple : Apple 専用実装（ImageIO / Core Image / Vision）。FlowCore のプロトコルを実装する。
let package = Package(
    name: "FlowKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .library(name: "FlowApple", targets: ["FlowApple"]),
    ],
    targets: [
        .target(name: "FlowCore"),
        .target(name: "FlowApple", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
