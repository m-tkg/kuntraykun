import SwiftUI
import AppKit
import KuntraykunCore

/// 設定の編集状態。変更は**即時反映**する（Apply/OK ボタンは持たない）。
@MainActor
final class SettingsViewModel: ObservableObject {
    /// 設定。変更されるたびに `onChange` で保存・反映する。
    @Published var settings: KuntraykunCore.Settings {
        didSet { onChange(settings) }
    }
    private let onChange: (KuntraykunCore.Settings) -> Void

    init(settings: KuntraykunCore.Settings, onChange: @escaping (KuntraykunCore.Settings) -> Void) {
        self.onChange = onChange
        self.settings = settings // init 内の代入では didSet は発火しない
    }
}

/// 設定ダイアログ本体。タブで機能ごとの設定を切り替える。
/// 機能を増やす場合は TabView 内にタブを追加する。「一般」は左端に置く。
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var loginItem: LoginItemController
    let catalog: [KunApp]

    @State private var loginItemError: String?

    var body: some View {
        // 変更は即時反映するため Cancel/Apply/OK ボタンは置かない。ウィンドウは閉じるボタンで閉じる。
        TabView {
            GeneralSettingsTab(loginItem: loginItem, errorMessage: $loginItemError)
                .tabItem { Text(L.string("tab.general")) }

            ManagedAppsSettingsTab(settings: $viewModel.settings.managedApps, catalog: catalog)
                .tabItem { Text(L.string("tab.managed_apps")) }
            // 将来の機能タブはここに追加する。
        }
        .padding()
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

                // ▲▼ ボタンで並べ替える。並び順がプルダウンの表示順になる。
                // （小さい設定ウィンドウでは List のドラッグ並べ替えが 3 行目以降で効かないことがあるため、
                //  確実に動くボタン方式にしている。）
                ScrollView {
                    VStack(spacing: 6) {
                        let apps = orderedCatalog
                        ForEach(Array(apps.enumerated()), id: \.element.id) { pair in
                            let index = pair.offset
                            let app = pair.element
                            HStack(spacing: 8) {
                                Toggle(isOn: binding(for: app.bundleID)) {
                                    HStack(spacing: 8) {
                                        Image(nsImage: Self.icon(for: app))
                                        Text(app.displayName)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button { reorder(from: index, to: index - 1) } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                Button { reorder(from: index, to: index + 1) } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == apps.count - 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            // 選択済みアプリが未起動のとき、メニューバーアイコンに黄三角の警告を出すか。
            Toggle(L.string("managed_apps.warn_not_running"), isOn: $settings.warnWhenAppsNotRunning)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 表示順（プルダウンの並び）に並べたカタログ。
    private var orderedCatalog: [KunApp] {
        KunAppMatcher.ordered(catalog, order: settings.orderedBundleIDs)
    }

    /// ▲▼ による並べ替え。表示中の順序を基底 bundle ID 配列として保存する。
    private func reorder(from: Int, to: Int) {
        var ids = orderedCatalog.map { IntegrationProtocol.baseBundleID($0.bundleID) }
        guard ids.indices.contains(from), to >= 0, to < ids.count else { return }
        let id = ids.remove(at: from)
        ids.insert(id, at: to)
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
