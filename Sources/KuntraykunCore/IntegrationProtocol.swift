import Foundation

/// kuntraykun と各 kun アプリ間の連携プロトコル（v1）の定数とエンコード規約。
///
/// 詳細仕様は `docs/kun-integration-protocol.md`。各 kun アプリ側はここと同じ
/// 通知名・userInfo キーを使って実装する。`DistributedNotificationCenter` を用い、
/// userInfo の値は文字列のみ（分散通知はプロパティリスト型のみ・非サンドボックス前提）。
public enum IntegrationProtocol {
    /// 集約ハブ（kuntraykun 本体）の bundle ID。
    public static let kuntraykunBundleID = "com.mtkg.kuntraykun"
    /// 管理対象アプリの bundle ID 接頭辞。
    public static let managedBundleIDPrefix = "com.mtkg."
    /// 管理対象アプリの bundle ID 末尾（kun シリーズの命名）。`com.mtkg.gogai` のような非 kun を除外する。
    public static let managedBundleIDSuffix = "kun"
    /// プロトコルバージョン。
    public static let version = "1"

    /// v2: 各アプリが「実際のメニューバーアイコン」を書き出す共有ディレクトリ
    /// （`~/Library/Application Support/` からの相対パス）。各アプリは `<基底bundleID>.png` を、
    /// テンプレート画像の場合は併せて空ファイル `<基底bundleID>.template` を書き出す。kuntraykun がこれを読んで一覧に表示する。
    public static let sharedIconDirRelativePath = "Kuntraykun/MenuBarIcons"

    // MARK: 通知名

    /// kuntraykun → 全アプリ。対象集合を知らせる（冪等ブロードキャスト）。
    public static let syncNotification = "com.mtkg.kuntraykun.sync"
    /// kuntraykun → 対象1アプリ。指定座標にメニューを出すよう依頼する。
    public static let showMenuNotification = "com.mtkg.kuntraykun.showMenu"
    /// アプリ → kuntraykun。連携対応アプリの起動を知らせる。
    public static let appLaunchedNotification = "com.mtkg.kun.appLaunched"

    // MARK: userInfo キー

    /// sync: カンマ区切りの対象 bundleID 群。
    public static let keyManaged = "managed"
    /// showMenu: 対象 bundleID。
    public static let keyTarget = "target"
    /// showMenu: スクリーン座標 X（左下原点）。
    public static let keyX = "x"
    /// showMenu: スクリーン座標 Y（左下原点）。
    public static let keyY = "y"
    /// appLaunched: 送信元 bundleID。
    public static let keyBundleID = "bundleID"
    /// appLaunched: プロトコルバージョン。
    public static let keyProtocol = "protocol"

    /// 末尾 `.local`（ローカル検証ビルド）を取り除いた基底 bundle ID。
    /// ローカルビルドでも本番 ID として突き合わせられるようにする。
    public static func baseBundleID(_ id: String) -> String {
        id.hasSuffix(".local") ? String(id.dropLast(".local".count)) : id
    }

    /// 対象集合を sync の `managed` 文字列へエンコードする（重複除去・ソート・カンマ区切り）。
    public static func encodeManaged<S: Sequence>(_ ids: S) -> String where S.Element == String {
        Set(ids).sorted().joined(separator: ",")
    }

    /// sync の `managed` 文字列を bundleID 配列へデコードする（空要素・空白は除去）。
    public static func decodeManaged(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
