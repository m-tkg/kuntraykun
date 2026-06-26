import Foundation

/// 検出した kun シリーズアプリ1つ分のメタ情報。
public struct KunApp: Equatable, Identifiable {
    /// bundle ID（`com.mtkg.<name>`）。一覧の同一性に使う。
    public let bundleID: String
    /// UI 表示用のアプリ名。
    public let displayName: String
    /// `.app` の場所。
    public let url: URL

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, url: URL) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.url = url
    }
}
