import AppKit
import KuntraykunCore

/// メニューバー常駐アイコンとメニューを管理する。
///
/// メニューを開くたびに `NSMenuDelegate.menuNeedsUpdate` で動的再構築し、
/// 「選択済み かつ 実行中」の kun アプリだけを一覧に並べる。各項目をクリックすると
/// そのアプリへ `showMenu` を依頼する（`onSelectApp`）。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem

    private let listProvider: () -> [KunApp]
    private let onSelectApp: (KunApp) -> Void
    private let openSettings: () -> Void
    private let checkForUpdate: () -> Void
    private let quitApp: () -> Void

    /// 新バージョンが利用可能ならそのタグ。メニュー再構築時に文言へ反映する。
    private var updateAvailableTag: String?
    /// 新版ありを示す赤バッジ（アイコン右下にオーバーレイ）。
    private var badgeView: NSView?
    /// 「アップデートあり」を報告してきた管理対象アプリの基底 bundle ID 集合（プルダウンの赤丸用）。
    private var appsWithUpdate: Set<String> = []

    private static var checkUpdateTitle: String { L.string("menu.check_update") }

    /// ローカル検証ビルド（バンドルID が `.local` で終わる）かどうか。
    private var isLocalBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".local")
    }

    init(
        listProvider: @escaping () -> [KunApp],
        onSelectApp: @escaping (KunApp) -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdate: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.listProvider = listProvider
        self.onSelectApp = onSelectApp
        self.openSettings = openSettings
        self.checkForUpdate = checkForUpdate
        self.quitApp = quit
        super.init()

        if let button = statusItem.button {
            if let template = Self.menuBarImage() {
                button.image = template
            } else if let symbol = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Kuntraykun") {
                button.image = symbol
            } else {
                button.title = "▣"
            }
            // ローカルビルドは「ローカル」を併記して本番と区別する。
            if isLocalBuild {
                button.title = " " + L.string("menu_bar.local")
                button.imagePosition = .imageLeading
            }
            installBadge(on: button)
        }

        // 動的メニュー。開くたびに menuNeedsUpdate で作り直す。
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// 新バージョンが利用可能なときに記録する（次回のメニュー再構築で文言に反映）。赤バッジも更新する。
    func setUpdateAvailable(tag: String) {
        updateAvailableTag = tag
        refreshBadge()
    }

    /// 最新（更新なし）状態に戻す。赤バッジも更新する。
    func clearUpdateAvailable() {
        updateAvailableTag = nil
        refreshBadge()
    }

    /// 管理対象アプリの「アップデートあり」集合を更新する（集約バッジとプルダウンの赤丸に反映）。
    func setAppsWithUpdate(_ ids: Set<String>) {
        appsWithUpdate = ids
        refreshBadge()
    }

    /// 自分の更新、またはいずれかの管理対象アプリの更新があれば赤バッジを表示する。
    private func refreshBadge() {
        badgeView?.isHidden = !(updateAvailableTag != nil || !appsWithUpdate.isEmpty)
    }

    /// 赤バッジをアイコン右下へオーバーレイする。位置はアイコン画像の幅基準で固定し、
    /// 「ローカル」テキスト併記時（imagePosition = .imageLeading）でも常にアイコングリフの右下に乗せる。
    private func installBadge(on button: NSStatusBarButton) {
        let size: CGFloat = 8
        let iconWidth = button.image?.size.width ?? 18
        let badge = UpdateBadgeView(diameter: size)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: size),
            badge.heightAnchor.constraint(equalToConstant: size),
            badge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: iconWidth - size),
            badge.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        badgeView = badge
    }

    /// ステータスボタンの左下のスクリーン座標（Cocoa 座標・左下原点）。`showMenu` の表示位置に使う。
    func buttonScreenPoint() -> CGPoint? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        return CGPoint(x: rectInScreen.minX, y: rectInScreen.minY)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 先頭にバージョン情報（操作不可）。ローカルビルドは併記する。
        var versionTitle = L.format("menu.version", UpdateService.currentVersion)
        if isLocalBuild { versionTitle += " (" + L.string("menu_bar.local") + ")" }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        // まとめ対象（選択済み かつ 実行中）アプリの一覧。
        let apps = listProvider()
        if apps.isEmpty {
            let empty = NSMenuItem(title: L.string("menu.no_apps"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for app in apps {
                let item = NSMenuItem(title: app.displayName, action: #selector(handleSelectApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app
                item.image = Self.appIcon(for: app)
                // アップデートありのアプリは行末に赤丸を付ける。
                if appsWithUpdate.contains(IntegrationProtocol.baseBundleID(app.bundleID)) {
                    item.attributedTitle = Self.titleWithUpdateDot(app.displayName)
                }
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        menu.addItem(menuItem(title: L.string("menu.settings"), action: #selector(handleOpenSettings), key: ","))
        let updateTitle = updateAvailableTag.map { L.format("menu.install_update", $0) } ?? Self.checkUpdateTitle
        menu.addItem(menuItem(title: updateTitle, action: #selector(handleCheckForUpdate), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.quit"), action: #selector(handleQuit), key: "q"))
    }

    // MARK: - アクション

    @objc private func handleSelectApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? KunApp else { return }
        onSelectApp(app)
    }
    @objc private func handleOpenSettings() { openSettings() }
    @objc private func handleCheckForUpdate() { checkForUpdate() }
    @objc private func handleQuit() { quitApp() }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - 画像

    /// 各 kun アプリのメニュー項目用アイコン（16pt）。各アプリのメニューバーアイコンに揃える。
    private static func appIcon(for app: KunApp) -> NSImage {
        KunAppIcon.image(for: app, size: 16)
    }

    /// 表示名の末尾に赤丸（●）を付けた属性付きタイトル（アップデートあり表示用）。
    private static func titleWithUpdateDot(_ name: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: name + "  ")
        result.append(NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor.systemRed]))
        return result
    }

    /// メニューバー用のテンプレート（モノクロ）画像。`Resources/MenuBarIcon.png` があれば使う。
    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        let height: CGFloat = 18
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }
}
