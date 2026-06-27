import Foundation

/// kun アプリの判定・絞り込みを行う純粋ロジック（AppKit 非依存・テスト対象）。
public enum KunAppMatcher {
    /// この bundle ID が kuntraykun に「まとめられる」対象たりうるか。
    /// kun シリーズ（`com.mtkg.<...>kun`）であり、かつ kuntraykun 自身（および `.local` 派生）でないこと。
    /// 末尾 `kun` の条件で、同じ `com.mtkg.*` でも非 kun のアプリ（例 `com.mtkg.gogai`）を除外する。
    public static func isManageable(bundleID: String) -> Bool {
        let base = IntegrationProtocol.baseBundleID(bundleID)
        return base.hasPrefix(IntegrationProtocol.managedBundleIDPrefix)
            && base.hasSuffix(IntegrationProtocol.managedBundleIDSuffix)
            && base != IntegrationProtocol.kuntraykunBundleID
    }

    /// カタログを表示順に並べる。`order`（基底 bundle ID 配列）に載っているものを先頭にその順で、
    /// 載っていないものを末尾に表示名昇順で続ける。`order` が空なら全て表示名昇順（従来動作）。
    public static func ordered(_ catalog: [KunApp], order: [String]) -> [KunApp] {
        var rank: [String: Int] = [:]
        for (i, id) in order.enumerated() where rank[id] == nil {
            rank[IntegrationProtocol.baseBundleID(id)] = i
        }
        let big = Int.max
        return catalog.sorted { a, b in
            let ra = rank[IntegrationProtocol.baseBundleID(a.bundleID)] ?? big
            let rb = rank[IntegrationProtocol.baseBundleID(b.bundleID)] ?? big
            if ra != rb { return ra < rb }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// メニューに表示する対象アプリ（= 選択済み かつ 実行中）を、`order` の順で返す。
    /// 比較は基底 bundle ID で行い、対象アプリがローカルビルドでも一致させる。
    public static func displayed(
        catalog: [KunApp],
        enabled: Set<String>,
        running: Set<String>,
        order: [String] = []
    ) -> [KunApp] {
        let enabledBase = Set(enabled.map(IntegrationProtocol.baseBundleID))
        let runningBase = Set(running.map(IntegrationProtocol.baseBundleID))
        return ordered(catalog, order: order).filter { app in
            let base = IntegrationProtocol.baseBundleID(app.bundleID)
            return enabledBase.contains(base) && runningBase.contains(base)
        }
    }
}
