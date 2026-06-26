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
}
