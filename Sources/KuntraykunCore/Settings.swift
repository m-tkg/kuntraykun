import Foundation

/// アプリ全体の設定。機能ごとにサブ構造体を持ち、機能追加時はここにプロパティを足して拡張する。
///
/// 前方/後方互換のため Codable は欠損キーを既定値で補完する（古い/新しい設定ファイルでも壊れない）。
public struct Settings: Codable, Equatable {
    /// まとめる対象アプリの設定。
    public var managedApps: ManagedAppsSettings

    public init(managedApps: ManagedAppsSettings = ManagedAppsSettings()) {
        self.managedApps = managedApps
    }

    /// 既定設定。
    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case managedApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.managedApps = try container.decodeIfPresent(ManagedAppsSettings.self, forKey: .managedApps)
            ?? ManagedAppsSettings()
    }
}

/// 「まとめる対象アプリ」の設定。kuntraykun が集約する kun アプリの bundle ID 集合を持つ。
public struct ManagedAppsSettings: Codable, Equatable {
    /// まとめる対象として選択された kun アプリの bundle ID 集合。
    public var enabledBundleIDs: Set<String>
    /// プルダウンに表示する順序（基底 bundle ID を並べた配列）。
    /// ここに無いアプリは末尾に表示名昇順で続く。空なら従来どおり全て表示名昇順。
    public var orderedBundleIDs: [String]

    public init(enabledBundleIDs: Set<String> = [], orderedBundleIDs: [String] = []) {
        self.enabledBundleIDs = enabledBundleIDs
        self.orderedBundleIDs = orderedBundleIDs
    }

    private enum CodingKeys: String, CodingKey {
        case enabledBundleIDs
        case orderedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabledBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledBundleIDs)
            ?? []
        self.orderedBundleIDs = try container.decodeIfPresent([String].self, forKey: .orderedBundleIDs)
            ?? []
    }
}
