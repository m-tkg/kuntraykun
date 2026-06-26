import AppKit
import KuntraykunCore

/// `/Applications` を走査して、まとめられる kun アプリ（`com.mtkg.*`）を検出する。
/// 純粋判定は `KunAppMatcher` に委ね、ここはファイルシステム IO のみ担う。
enum KunAppScanner {
    /// 既定の検出元（ユーザー指定どおり `/Applications`）。
    static let defaultDirectory = URL(fileURLWithPath: "/Applications")

    /// `directory` 直下の `.app` を調べ、kun アプリの一覧を表示名昇順で返す。
    static func scan(in directory: URL = defaultDirectory) -> [KunApp] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        var apps: [KunApp] = []
        for url in entries where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  KunAppMatcher.isManageable(bundleID: bundleID)
            else { continue }
            let name = fm.displayName(atPath: url.path)
            apps.append(KunApp(bundleID: bundleID, displayName: name, url: url))
        }
        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// 現在実行中のアプリの bundle ID 集合。
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }
}
