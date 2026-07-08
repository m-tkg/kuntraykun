// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kuntraykun",
    // ローカライズ済みリソース（en/ja）を持つため既定言語を指定する。
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 連携プロトコル定数・メニュースナップショットモデルの共有ライブラリ（kun シリーズ共通）
        .package(url: "https://github.com/m-tkg/kunkit.git", from: "1.3.0")
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit に依存しない判定ロジック・設定モデル
        .target(
            name: "KuntraykunCore",
            dependencies: [
                .product(name: "KunIntegrationProtocol", package: "kunkit")
            ]
        ),
        // 実行ファイル本体: メニューバー常駐・アプリ検出・分散通知連携・設定UI
        .executableTarget(
            name: "Kuntraykun",
            dependencies: [
                "KuntraykunCore",
                .product(name: "KunIntegrationProtocol", package: "kunkit"),
                .product(name: "KunUpdateKit", package: "kunkit"),
                .product(name: "KunSupport", package: "kunkit"),
                .product(name: "KunAppKit", package: "kunkit"),
            ],
            // en.lproj / ja.lproj の Localizable.strings をリソースバンドルに含める。
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KuntraykunCoreTests",
            dependencies: ["KuntraykunCore"]
        ),
    ]
)
