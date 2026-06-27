import SwiftUI
import AppKit
import KuntraykunCore

/// 設定ダイアログの編集状態。編集は作業コピー上で行い、Apply/OK で確定する。
@MainActor
final class SettingsViewModel: ObservableObject {
    /// 編集中の作業コピー。
    @Published var settings: KuntraykunCore.Settings
    /// 直近に確定（Apply/OK）した内容。Cancel 時の復帰先。
    private var committed: KuntraykunCore.Settings
    private let onApply: (KuntraykunCore.Settings) -> Void

    init(settings: KuntraykunCore.Settings, onApply: @escaping (KuntraykunCore.Settings) -> Void) {
        self.settings = settings
        self.committed = settings
        self.onApply = onApply
    }

    /// 未確定の変更があるか。
    var hasChanges: Bool { settings != committed }

    /// 作業コピーを確定し保存・反映する。
    func apply() {
        committed = settings
        onApply(settings)
    }

    /// 未確定の変更を破棄して直近の確定内容に戻す。
    func revert() {
        settings = committed
    }
}

/// 設定ダイアログ本体。タブで機能ごとの設定を切り替える。
/// 機能を増やす場合は TabView 内にタブを追加する。「一般」は左端に置く。
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var loginItem: LoginItemController
    let catalog: [KunApp]
    let onClose: () -> Void

    @State private var loginItemError: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsTab(loginItem: loginItem, errorMessage: $loginItemError)
                    .tabItem { Text(L.string("tab.general")) }

                ManagedAppsSettingsTab(settings: $viewModel.settings.managedApps, catalog: catalog)
                    .tabItem { Text(L.string("tab.managed_apps")) }
                // 将来の機能タブはここに追加する。
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button(L.string("button.cancel")) {
                    viewModel.revert()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button(L.string("button.apply")) {
                    viewModel.apply()
                }
                .disabled(!viewModel.hasChanges)

                Button(L.string("button.ok")) {
                    viewModel.apply()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 360)
        .alert(L.string("alert.error.title"), isPresented: Binding(
            get: { loginItemError != nil },
            set: { if !$0 { loginItemError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
    }
}

/// 「一般」タブ。ログイン時の自動起動とバージョン表示。
struct GeneralSettingsTab: View {
    @ObservedObject var loginItem: LoginItemController
    @SwiftUI.Binding var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ログイン項目はシステム側が source of truth。トグル操作で即時反映する。
            Toggle(L.string("settings.launch_at_login"), isOn: Binding(
                get: { loginItem.isEnabled },
                set: { newValue in
                    if let message = loginItem.setEnabled(newValue) {
                        errorMessage = message
                    }
                }
            ))

            Text(L.format("settings.version", UpdateService.currentVersion))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「管理アプリ」タブ。検出した kun アプリの中から、1アイコンにまとめる対象を選ぶ。
struct ManagedAppsSettingsTab: View {
    @SwiftUI.Binding var settings: ManagedAppsSettings
    let catalog: [KunApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if catalog.isEmpty {
                Text(L.string("managed_apps.empty"))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L.string("managed_apps.description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // ドラッグで並べ替え可能なリスト。並び順がプルダウンの表示順になる。
                List {
                    ForEach(orderedCatalog) { app in
                        Toggle(isOn: binding(for: app.bundleID)) {
                            HStack(spacing: 8) {
                                Image(nsImage: Self.icon(for: app))
                                Text(app.displayName)
                            }
                        }
                    }
                    .onMove(perform: move)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 表示順（プルダウンの並び）に並べたカタログ。
    private var orderedCatalog: [KunApp] {
        KunAppMatcher.ordered(catalog, order: settings.orderedBundleIDs)
    }

    /// ドラッグ並べ替え。表示中の順序を基底 bundle ID 配列として保存する。
    private func move(from source: IndexSet, to destination: Int) {
        var ids = orderedCatalog.map { IntegrationProtocol.baseBundleID($0.bundleID) }
        ids.move(fromOffsets: source, toOffset: destination)
        settings.orderedBundleIDs = ids
    }

    /// 対象集合への所属を表す Toggle 用 Binding。
    private func binding(for bundleID: String) -> SwiftUI.Binding<Bool> {
        SwiftUI.Binding(
            get: { settings.enabledBundleIDs.contains(bundleID) },
            set: { isOn in
                if isOn { settings.enabledBundleIDs.insert(bundleID) }
                else { settings.enabledBundleIDs.remove(bundleID) }
            }
        )
    }

    private static func icon(for app: KunApp) -> NSImage {
        KunAppIcon.image(for: app, size: 18)
    }
}
