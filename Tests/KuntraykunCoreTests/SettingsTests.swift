import XCTest
@testable import KuntraykunCore

final class SettingsTests: XCTestCase {
    func testDefaultHasNoEnabledApps() {
        XCTAssertTrue(Settings.default.managedApps.enabledBundleIDs.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var s = Settings.default
        s.managedApps.enabledBundleIDs = ["com.mtkg.clipkun", "com.mtkg.keykun"]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testMissingKeysFallBackToDefault() throws {
        // 空の JSON でも壊れず既定にフォールバックする（前方/後方互換）。
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, Settings.default)
    }

    func testMissingEnabledBundleIDsFallsBackToEmpty() throws {
        let data = Data(#"{"managedApps":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertTrue(decoded.managedApps.enabledBundleIDs.isEmpty)
    }

    func testWarnWhenAppsNotRunningDefaultsToTrue() {
        XCTAssertTrue(Settings.default.managedApps.warnWhenAppsNotRunning)
    }

    func testMissingWarnFlagFallsBackToTrue() throws {
        // 旧フォーマット（フラグ無し）でも既定 true にフォールバックする（後方互換）。
        let data = Data(#"{"managedApps":{"enabledBundleIDs":["com.mtkg.clipkun"]}}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertTrue(decoded.managedApps.warnWhenAppsNotRunning)
    }

    func testWarnFlagRoundTripsThroughJSON() throws {
        var s = Settings.default
        s.managedApps.warnWhenAppsNotRunning = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertFalse(decoded.managedApps.warnWhenAppsNotRunning)
    }
}
