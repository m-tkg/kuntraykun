import Foundation
import OSLog
import KuntraykunCore
import KunIntegrationProtocol

private let log = Logger(subsystem: "com.mtkg.kuntraykun", category: "menu-snapshot")

/// kun アプリが書き出したメニュースナップショット（連携 v4）の in-memory キャッシュ。
///
/// `menuSnapshot` 通知を受けたタイミングでのみ共有ファイルを読み込む。
/// 「サブメニュー対応かどうか」の判定は本セッション中の通知受信（= キャッシュの有無）で行い、
/// 旧バージョンへ戻したアプリが残した stale ファイルを誤って使わないよう、
/// 起動時のファイル先読みはしない。
@MainActor
final class MenuSnapshotStore {
    private var cache: [String: MenuSnapshot] = [:]

    /// 各アプリがスナップショット JSON を書き出す共有ディレクトリ（連携 v4）。
    static var sharedMenuDir: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(IntegrationProtocol.sharedMenuDirRelativePath, isDirectory: true)
    }

    /// `menuSnapshot` 通知を受けて、その基底 bundleID の共有ファイルを読み直す。
    func reload(baseID: String) {
        guard let dir = Self.sharedMenuDir else { return }
        let url = dir.appendingPathComponent("\(baseID).json")
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try MenuSnapshot.decode(data)
            cache[baseID] = snapshot
            log.info("menu snapshot loaded: \(baseID, privacy: .public) gen=\(snapshot.generation, privacy: .public) items=\(snapshot.items.count)")
        } catch {
            // 読めない/壊れている場合は古いキャッシュも破棄してフォールバック（従来の popUp）に落とす。
            cache[baseID] = nil
            log.error("menu snapshot load failed: \(baseID, privacy: .public) \(error.localizedDescription, privacy: .public)")
        }
    }

    /// キャッシュ済みスナップショット。nil ならサブメニュー非対応（従来動作へフォールバック）。
    func snapshot(for baseID: String) -> MenuSnapshot? {
        cache[baseID]
    }
}
