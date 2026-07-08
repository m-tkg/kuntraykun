import AppKit
import KuntraykunCore
import KunIntegrationProtocol

/// メニュースナップショット（連携 v4）から NSMenu を再構築する。
///
/// 項目クリックはアクションを直接実行できないため、`onInvoke(itemID)` 経由で
/// 対象アプリへ `invokeMenuItem` を依頼する。
@MainActor
enum KunSubmenuBuilder {
    /// スナップショット全体をサブメニューにする。
    static func build(from snapshot: MenuSnapshot, onInvoke: @escaping (String) -> Void) -> NSMenu {
        menu(for: snapshot.items, onInvoke: onInvoke)
    }

    private static func menu(for nodes: [MenuItemNode], onInvoke: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        // enabled はスナップショットの値をそのまま使う（レスポンダチェーンでの自動判定は不可）。
        menu.autoenablesItems = false
        for node in nodes {
            if node.separator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            item.isEnabled = node.enabled
            item.state = state(for: node.state)
            if !node.children.isEmpty {
                item.submenu = Self.menu(for: node.children, onInvoke: onInvoke)
            } else if node.enabled {
                let action = InvokeAction { onInvoke(node.id) }
                item.target = action
                item.action = #selector(InvokeAction.fire(_:))
                // NSMenuItem.target は弱参照のため、representedObject で保持する。
                item.representedObject = action
            }
            menu.addItem(item)
        }
        return menu
    }

    private static func state(for state: MenuItemState) -> NSControl.StateValue {
        switch state {
        case .off: return .off
        case .on: return .on
        case .mixed: return .mixed
        }
    }
}

/// クリックをクロージャへ橋渡しする target。
private final class InvokeAction: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: NSMenuItem) {
        handler()
    }
}
