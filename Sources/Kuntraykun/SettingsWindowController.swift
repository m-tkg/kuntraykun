import AppKit
import KunAppKit
import SwiftUI
import KuntraykunCore

/// 設定ウィンドウ（SwiftUI の SettingsView を NSWindow にホストする）。
/// 表示中は Dock アイコンも出すため、表示/クローズに合わせて activation policy を切り替える。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel: SettingsViewModel
    private let catalog: [KunApp]
    private let loginItem = LoginItemController(
        requiresApprovalMessage: { L.string("login_item.requires_approval") })

    init(
        initialSettings: KuntraykunCore.Settings,
        catalog: [KunApp],
        onChange: @escaping (KuntraykunCore.Settings) -> Void
    ) {
        self.viewModel = SettingsViewModel(settings: initialSettings, onChange: onChange)
        self.catalog = catalog
        super.init()
    }

    func show() {
        // 外部（システム設定）で変更された可能性があるため最新状態に同期する。
        loginItem.refresh()
        if window == nil {
            let rootView = SettingsView(
                viewModel: viewModel,
                loginItem: loginItem,
                catalog: catalog
            )
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = L.string("settings.window.title")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 360))
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        // 設定表示中は Dock にも出す。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 閉じたらメニューバー常駐のみに戻す（Dock アイコンを隠す）。
        NSApp.setActivationPolicy(.accessory)
    }
}
