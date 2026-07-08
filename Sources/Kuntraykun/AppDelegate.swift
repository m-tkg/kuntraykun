import AppKit
import KunAppKit
import KunIntegrationProtocol
import KunSupport
import KunUpdateKit
import OSLog
import KuntraykunCore

private let log = Logger(subsystem: "com.mtkg.kuntraykun", category: "app")

/// アプリ本体。設定の読込・反映、ステータスバー UI と設定ウィンドウの配線、
/// 連携ハブ（分散通知）の起動を担う。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = KunSettingsStore<Settings>(
        url: KunSettingsStore<Settings>.defaultURL(appFolderName: "Kuntraykun"), defaultValue: .default)
    private var settings = Settings.default

    /// /Applications から検出した kun アプリのカタログ。
    private var catalog: [KunApp] = []

    private var statusBar: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private lazy var hub = IntegrationHub(
        enabledProvider: { [weak self] in self?.settings.managedApps.enabledBundleIDs ?? [] },
        onUpdateState: { [weak self] baseID, hasUpdate in self?.handleUpdateState(baseID, hasUpdate) },
        onMenuSnapshot: { [weak self] baseID in self?.menuSnapshots.reload(baseID: baseID) }
    )
    /// 各アプリのメニュースナップショット（連携 v4）のキャッシュ。
    private let menuSnapshots = MenuSnapshotStore()
    /// 「アップデートあり」を報告してきた管理対象アプリの基底 bundle ID 集合。
    private var appsWithUpdate: Set<String> = []

    // アップデート関連。
    private let updateService = UpdateService()
    private let selfUpdater = SelfUpdater(appName: "Kuntraykun")
    private var availableRelease: ReleaseInfo?

    /// 未起動警告の定期再評価用タイマー。
    private var warningRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = store.load()
        catalog = KunAppScanner.scan()

        statusBar = StatusBarController(
            listProvider: { [weak self] in self?.displayedApps() ?? [] },
            onSelectApp: { [weak self] app in self?.showAppMenu(app) },
            snapshotProvider: { [weak self] app in
                self?.menuSnapshots.snapshot(for: IntegrationProtocol.baseBundleID(app.bundleID))
            },
            onInvokeItem: { [weak self] app, itemID, generation in
                self?.hub.invokeMenuItem(target: app.bundleID, itemID: itemID, generation: generation)
            },
            onMenuOpened: { [weak self] apps in
                self?.hub.requestMenu(targets: apps.map(\.bundleID))
            },
            openSettings: { [weak self] in self?.openSettings() },
            checkForUpdate: { [weak self] in self?.startUpdateCheck(interactive: true) },
            quit: { NSApp.terminate(nil) }
        )

        // 連携ハブを開始（起動時の sync をブロードキャスト）。
        hub.start()
        // サブメニュー（連携 v4）のキャッシュを温める。応答が来たアプリだけサブメニュー表示になる。
        hub.requestMenu(targets: settings.managedApps.enabledBundleIDs)

        // 管理対象アプリの起動/終了で警告バッジを更新する（メニューを開かなくても常時最新化）。
        startWarningRefreshTimer()
        refreshWarning()

        // 起動時にサイレントで更新チェック（あればメニュー文言を変更）。
        startUpdateCheck(interactive: false)
    }

    /// 数秒おきに未起動警告を再評価する。
    ///
    /// 当初は `NSWorkspace.didLaunchApplicationNotification` /
    /// `didTerminateApplicationNotification` の購読で即時反映しようとしたが、
    /// これらの通知は LSUIElement（Dockアイコンなしのメニューバー常駐）アプリの
    /// 起動/終了では発火しないことを実機で確認した（通常の Dock アプリでは発火する）。
    /// kun アプリは全て LSUIElement のため、その方式では警告が一切更新されなかった。
    /// そのため確実に動く軽量なポーリングに切り替える。
    private func startWarningRefreshTimer() {
        warningRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWarning() }
        }
    }

    /// 選択済みの管理対象アプリが未起動かを評価し、メニューバーアイコンの警告バッジへ反映する。
    /// 設定で警告が無効なら常に非表示にする。
    /// 併せて「更新あり」バッジも再評価する（報告したアプリの終了・設定変更を追随させる）。
    private func refreshWarning() {
        let missing = settings.managedApps.warnWhenAppsNotRunning
            && KunAppMatcher.hasMissingManagedApps(
                catalog: catalog,
                enabled: settings.managedApps.enabledBundleIDs,
                running: KunAppScanner.runningBundleIDs())
        statusBar?.setManagedAppsMissing(missing)
        pushAppsWithUpdate()
    }

    /// 管理対象アプリから届いた「アップデートあり/なし」を集約し、アイコンの赤バッジと
    /// プルダウンの赤丸に反映する。
    private func handleUpdateState(_ baseID: String, _ hasUpdate: Bool) {
        let changed: Bool
        if hasUpdate { changed = appsWithUpdate.insert(baseID).inserted }
        else { changed = appsWithUpdate.remove(baseID) != nil }
        if changed { pushAppsWithUpdate() }
    }

    /// 「更新あり」集合を**プルダウンに表示される対象（選択済み かつ 実行中）に絞って**反映する。
    /// 管理対象外・終了済みのアプリの報告でバッジだけが点く（赤丸の行が無いのに原因が見えない）
    /// 状態を防ぐ。生の報告は appsWithUpdate に保持し、後から選択/起動されたら反映される。
    private func pushAppsWithUpdate() {
        let displayedBase = Set(displayedApps().map { IntegrationProtocol.baseBundleID($0.bundleID) })
        statusBar?.setAppsWithUpdate(appsWithUpdate.intersection(displayedBase))
    }

    /// メニューに表示する対象アプリ（選択済み かつ 実行中）。
    private func displayedApps() -> [KunApp] {
        KunAppMatcher.displayed(
            catalog: catalog,
            enabled: settings.managedApps.enabledBundleIDs,
            running: KunAppScanner.runningBundleIDs(),
            order: settings.managedApps.orderedBundleIDs
        )
    }

    /// 対象アプリへ、自分のアイコン直下にメニューを出すよう依頼する。
    /// （一覧は実行中のものだけなので、ここでは起動済み前提）
    private func showAppMenu(_ app: KunApp) {
        guard let point = statusBar?.buttonScreenPoint() else {
            log.error("status button point unavailable")
            return
        }
        hub.showMenu(target: app.bundleID, at: point)
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                initialSettings: settings,
                catalog: catalog,
                onChange: { [weak self] newSettings in
                    guard let self else { return }
                    // 変更は即時反映: 保存して、対象集合の変化を即ブロードキャストし各アプリのアイコン表示を更新させる。
                    self.settings = newSettings
                    try? self.store.save(newSettings)
                    self.hub.broadcastSync()
                    // 追加されたアプリのサブメニューを次のオープンまでに用意する。
                    self.hub.requestMenu(targets: newSettings.managedApps.enabledBundleIDs)
                    // 対象集合や警告設定の変更を未起動警告に即反映する。
                    self.refreshWarning()
                }
            )
        }
        settingsWindowController?.show()
    }

    // MARK: - アップデート

    /// 最新リリースを取得してバージョン比較する。
    /// interactive=false: 起動時のサイレントチェック（結果はメニュー文言に反映するのみ）。
    /// interactive=true : メニューからの手動チェック（結果をダイアログで提示）。
    private func startUpdateCheck(interactive: Bool) {
        Task { @MainActor in
            do {
                let release = try await updateService.fetchLatestRelease()
                let isNewer = VersionComparator.isNewer(
                    tag: release.tagName, than: UpdateService.currentVersion)
                if isNewer {
                    availableRelease = release
                    statusBar?.setUpdateAvailable(tag: release.tagName)
                } else {
                    availableRelease = nil
                    statusBar?.clearUpdateAvailable()
                }
                if interactive {
                    if isNewer {
                        promptInstall(release)
                    } else {
                        showInfo(L.format("update.latest", UpdateService.currentVersion))
                    }
                }
            } catch {
                log.error("update check failed: \(error.localizedDescription, privacy: .public)")
                if interactive {
                    showError(L.format("update.check_failed", error.localizedDescription))
                }
            }
        }
    }

    private func promptInstall(_ release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.format("update.available.title", release.tagName)
        alert.informativeText = L.format("update.available.body", UpdateService.currentVersion)
        alert.addButton(withTitle: L.string("update.button.update"))
        alert.addButton(withTitle: L.string("update.button.open_release"))
        alert.addButton(withTitle: L.string("button.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func performUpdate(_ release: ReleaseInfo) {
        Task { @MainActor in
            do {
                try await selfUpdater.performUpdate(to: release)
                // 成功時はアプリが終了するためここには戻らない。
            } catch {
                log.error("self-update failed: \(error.localizedDescription, privacy: .public)")
                showError(L.format("update.failed", error.localizedDescription))
            }
        }
    }

    private func showInfo(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kuntraykun"
        alert.informativeText = text
        alert.runModal()
    }

    private func showError(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.string("alert.error.title")
        alert.informativeText = text
        alert.runModal()
    }
}
