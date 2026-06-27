import AppKit
import KuntraykunCore

/// kun アプリの一覧表示に使うアイコンを解決する。
enum KunAppIcon {
    /// 各アプリが書き出した「実際のメニューバーアイコン」の共有ディレクトリ。
    /// 連携プロトコル v2: 各アプリが現在のステータスアイコンをここに PNG で書き出す（色・状態込み）。
    private static var sharedIconDir: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(IntegrationProtocol.sharedIconDirRelativePath, isDirectory: true)
    }

    /// 一覧に表示するアイコンを次の優先順で解決する:
    /// 1. 各アプリが書き出した実アイコン（共有ディレクトリの `<基底ID>.png`。色・状態をそのまま反映。
    ///    `<基底ID>.template` があればテンプレート扱い）
    /// 2. アプリバンドル内の `Contents/Resources/MenuBarIcon.png`（テンプレート）
    /// 3. Finder のアプリアイコン
    static func image(for app: KunApp, size: CGFloat) -> NSImage {
        let baseID = IntegrationProtocol.baseBundleID(app.bundleID)

        if let dir = sharedIconDir {
            let pngURL = dir.appendingPathComponent("\(baseID).png")
            if let image = NSImage(contentsOf: pngURL) {
                resize(image, to: size)
                let markerPath = dir.appendingPathComponent("\(baseID).template").path
                image.isTemplate = FileManager.default.fileExists(atPath: markerPath)
                return image
            }
        }

        let menuIconURL = app.url.appendingPathComponent("Contents/Resources/MenuBarIcon.png")
        if let image = NSImage(contentsOf: menuIconURL) {
            resize(image, to: size)
            image.isTemplate = true
            return image
        }

        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    /// アスペクト比を保って高さ `size` に合わせる。
    private static func resize(_ image: NSImage, to size: CGFloat) {
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: size * aspect, height: size)
    }
}
