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
        }

        // 動的メニュー。開くたびに menuNeedsUpdate で作り直す。
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// 新バージョンが利用可能なときに記録する（次回のメニュー再構築で文言に反映）。
    func setUpdateAvailable(tag: String) { updateAvailableTag = tag }

    /// 最新（更新なし）状態に戻す。
    func clearUpdateAvailable() { updateAvailableTag = nil }

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

    /// 各 kun アプリのアイコン（メニュー項目用に 16pt）。
    private static func appIcon(for app: KunApp) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
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
