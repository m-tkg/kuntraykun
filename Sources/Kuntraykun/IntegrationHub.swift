import AppKit
import OSLog
import KuntraykunCore

private let log = Logger(subsystem: "com.mtkg.kuntraykun", category: "integration")

/// kuntraykun 側の連携プロトコル送受信（`DistributedNotificationCenter`）。
///
/// - `sync` を全 kun アプリへブロードキャストし、対象集合（隠すべきアプリ）を伝える。
/// - メニュー項目クリック時に `showMenu` を対象アプリへ送り、自分のアイコン直下にメニューを出させる。
/// - kun アプリの `appLaunched` を観測し、起動直後のアプリへ最新の `sync` を送り返す。
///
/// 仕様の詳細は `docs/kun-integration-protocol.md` を参照。
@MainActor
final class IntegrationHub {
    private let center = DistributedNotificationCenter.default()
    /// 現在の対象 bundle ID 集合を取得するクロージャ（AppDelegate の設定を参照）。
    private let enabledProvider: () -> Set<String>
    /// 各アプリの「アップデートあり」状態が届いたときの通知（基底 bundleID, あり/なし）。
    private let onUpdateState: (String, Bool) -> Void
    /// 各アプリがメニュースナップショットを書き出したときの通知（基底 bundleID）（v4）。
    private let onMenuSnapshot: (String) -> Void
    private var appLaunchedObserver: NSObjectProtocol?
    private var updateStateObserver: NSObjectProtocol?
    private var menuSnapshotObserver: NSObjectProtocol?

    init(enabledProvider: @escaping () -> Set<String>,
         onUpdateState: @escaping (String, Bool) -> Void,
         onMenuSnapshot: @escaping (String) -> Void) {
        self.enabledProvider = enabledProvider
        self.onUpdateState = onUpdateState
        self.onMenuSnapshot = onMenuSnapshot
    }

    deinit {
        if let observer = appLaunchedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = updateStateObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = menuSnapshotObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// 観測を開始し、起動時の `sync` を送る。
    func start() {
        appLaunchedObserver = center.addObserver(
            forName: Notification.Name(IntegrationProtocol.appLaunchedNotification),
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                let id = note.userInfo?[IntegrationProtocol.keyBundleID] as? String ?? "?"
                log.info("appLaunched from \(id, privacy: .public); resending sync")
                self?.broadcastSync()
            }
        }
        // 各アプリの「アップデートあり」状態を観測する（v3）。
        updateStateObserver = center.addObserver(
            forName: Notification.Name(IntegrationProtocol.updateStateNotification),
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let id = note.userInfo?[IntegrationProtocol.keyBundleID] as? String else { return }
                let hasUpdate = (note.userInfo?[IntegrationProtocol.keyHasUpdate] as? String) == "1"
                self?.onUpdateState(IntegrationProtocol.baseBundleID(id), hasUpdate)
            }
        }
        // 各アプリの「メニュースナップショットを書き出した」通知を観測する（v4）。
        menuSnapshotObserver = center.addObserver(
            forName: Notification.Name(IntegrationProtocol.menuSnapshotNotification),
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let id = note.userInfo?[IntegrationProtocol.keyBundleID] as? String else { return }
                self?.onMenuSnapshot(IntegrationProtocol.baseBundleID(id))
            }
        }
        broadcastSync()
    }

    /// 現在の対象集合を全アプリへブロードキャストする（起動時・設定変更時・appLaunched 受信時）。
    func broadcastSync() {
        let managed = IntegrationProtocol.encodeManaged(enabledProvider())
        center.postNotificationName(
            Notification.Name(IntegrationProtocol.syncNotification),
            object: nil,
            userInfo: [IntegrationProtocol.keyManaged: managed],
            deliverImmediately: true
        )
    }

    /// 対象アプリ群に、メニュースナップショットの書き出しを依頼する（v4）。
    /// 起動時・設定変更時のキャッシュ温めと、メニューを開くたびの更新（次回オープンに反映）に使う。
    func requestMenu<S: Sequence>(targets: S) where S.Element == String {
        let encoded = IntegrationProtocol.encodeManaged(targets.map(IntegrationProtocol.baseBundleID))
        guard !encoded.isEmpty else { return }
        center.postNotificationName(
            Notification.Name(IntegrationProtocol.requestMenuNotification),
            object: nil,
            userInfo: [IntegrationProtocol.keyTargets: encoded],
            deliverImmediately: true
        )
    }

    /// 対象アプリに、サブメニューでクリックされた項目の実行を依頼する（v4）。
    func invokeMenuItem(target bundleID: String, itemID: String, generation: String) {
        center.postNotificationName(
            Notification.Name(IntegrationProtocol.invokeMenuItemNotification),
            object: nil,
            userInfo: [
                IntegrationProtocol.keyTarget: IntegrationProtocol.baseBundleID(bundleID),
                IntegrationProtocol.keyItemID: itemID,
                IntegrationProtocol.keyGeneration: generation,
            ],
            deliverImmediately: true
        )
    }

    /// 対象アプリに、指定スクリーン座標へ自分のメニューを出すよう依頼する。
    func showMenu(target bundleID: String, at point: CGPoint) {
        center.postNotificationName(
            Notification.Name(IntegrationProtocol.showMenuNotification),
            object: nil,
            userInfo: [
                IntegrationProtocol.keyTarget: IntegrationProtocol.baseBundleID(bundleID),
                IntegrationProtocol.keyX: String(format: "%.1f", point.x),
                IntegrationProtocol.keyY: String(format: "%.1f", point.y),
            ],
            deliverImmediately: true
        )
    }
}
