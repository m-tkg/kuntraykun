import AppKit

/// 選択済みの管理対象アプリが起動していないときに、メニューバーアイコンの右下へ重ねる
/// 黄色い三角の警告バッジ。
///
/// ベースアイコンは `isTemplate = true`（明暗で自動着色）を保つため、色付きの警告は画像へ
/// 焼き込まず、この独立した view をオーバーレイして表示/非表示を切り替える（更新ありの
/// `UpdateBadgeView` と同じ方針）。SF Symbol `exclamationmark.triangle.fill` を黄色で描く。
final class WarningBadgeView: NSImageView {
    init(diameter: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        let config = NSImage.SymbolConfiguration(pointSize: diameter, weight: .bold)
        image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                        accessibilityDescription: "Managed app not running")?
            .withSymbolConfiguration(config)
        // テンプレート扱いを外し、色（黄色）をそのまま表示する。
        image?.isTemplate = false
        contentTintColor = .systemYellow
        imageScaling = .scaleProportionallyUpOrDown
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
