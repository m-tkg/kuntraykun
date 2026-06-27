import AppKit
import KuntraykunCore

/// kun アプリの一覧表示に使うアイコンを解決する。
enum KunAppIcon {
    /// 各アプリの**メニューバーアイコン**（`<App>.app/Contents/Resources/MenuBarIcon.png`）を返す。
    /// これにより一覧の見た目を、各アプリがメニューバーに出すアイコンに揃える（アプリ側の改修は不要）。
    /// 単体 PNG を持たないアプリ（アセットカタログ内包の gitkun 等）は、Finder のアプリアイコンにフォールバックする。
    static func image(for app: KunApp, size: CGFloat) -> NSImage {
        let menuIconURL = app.url.appendingPathComponent("Contents/Resources/MenuBarIcon.png")
        if let image = NSImage(contentsOf: menuIconURL) {
            // メニューバー同様にテンプレート（モノクロ）で描画し、サイズはアスペクト比を保って合わせる。
            let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
            image.size = NSSize(width: size * aspect, height: size)
            image.isTemplate = true
            return image
        }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
