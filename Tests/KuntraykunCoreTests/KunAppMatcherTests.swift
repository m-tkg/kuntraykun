import XCTest
@testable import KuntraykunCore

final class KunAppMatcherTests: XCTestCase {
    private func app(_ bundleID: String, _ name: String) -> KunApp {
        KunApp(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    // MARK: isManageable

    func testManageableForKunApps() {
        XCTAssertTrue(KunAppMatcher.isManageable(bundleID: "com.mtkg.clipkun"))
        XCTAssertTrue(KunAppMatcher.isManageable(bundleID: "com.mtkg.keykun"))
    }

    func testLocalBuildOfKunAppIsManageable() {
        XCTAssertTrue(KunAppMatcher.isManageable(bundleID: "com.mtkg.clipkun.local"))
    }

    func testKuntraykunItselfIsNotManageable() {
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.mtkg.kuntraykun"))
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.mtkg.kuntraykun.local"))
    }

    func testNonMtkgBundleIsNotManageable() {
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.apple.Safari"))
    }

    func testNonKunMtkgAppIsNotManageable() {
        // 同じ com.mtkg.* でも末尾が kun でないアプリ（例 Gogai）は対象外。
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.mtkg.gogai"))
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.mtkg.gogai.local"))
    }

    func testNonMtkgKunAppIsNotManageable() {
        // 末尾 kun でも com.mtkg. 以外は対象外（他者の "kun" アプリを拾わない）。
        XCTAssertFalse(KunAppMatcher.isManageable(bundleID: "com.example.kun"))
    }

    // MARK: displayed

    func testDisplayedKeepsOnlyEnabledAndRunningSortedByName() {
        let catalog = [
            app("com.mtkg.snapperkun", "Snapperkun"),
            app("com.mtkg.clipkun", "Clipkun"),
            app("com.mtkg.keykun", "Keykun"),
        ]
        let result = KunAppMatcher.displayed(
            catalog: catalog,
            enabled: ["com.mtkg.clipkun", "com.mtkg.keykun"],
            running: ["com.mtkg.clipkun", "com.mtkg.snapperkun"]
        )
        // enabled ∩ running = {clipkun}
        XCTAssertEqual(result.map(\.bundleID), ["com.mtkg.clipkun"])
    }

    func testDisplayedSortsByDisplayName() {
        let catalog = [
            app("com.mtkg.snapperkun", "Snapperkun"),
            app("com.mtkg.clipkun", "Clipkun"),
        ]
        let result = KunAppMatcher.displayed(
            catalog: catalog,
            enabled: ["com.mtkg.snapperkun", "com.mtkg.clipkun"],
            running: ["com.mtkg.snapperkun", "com.mtkg.clipkun"]
        )
        XCTAssertEqual(result.map(\.displayName), ["Clipkun", "Snapperkun"])
    }

    func testDisplayedMatchesRunningLocalBuildAgainstEnabledBaseID() {
        // 設定では本番 ID を選択、実行中はローカルビルド ID でも一致させる。
        let catalog = [app("com.mtkg.clipkun", "Clipkun")]
        let result = KunAppMatcher.displayed(
            catalog: catalog,
            enabled: ["com.mtkg.clipkun"],
            running: ["com.mtkg.clipkun.local"]
        )
        XCTAssertEqual(result.map(\.bundleID), ["com.mtkg.clipkun"])
    }

    func testDisplayedEmptyWhenNoneRunning() {
        let catalog = [app("com.mtkg.clipkun", "Clipkun")]
        let result = KunAppMatcher.displayed(
            catalog: catalog, enabled: ["com.mtkg.clipkun"], running: [])
        XCTAssertTrue(result.isEmpty)
    }
}
