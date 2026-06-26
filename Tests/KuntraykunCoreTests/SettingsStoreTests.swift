import XCTest
@testable import KuntraykunCore

final class SettingsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kuntraykun-test-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }

    func testLoadReturnsDefaultWhenFileMissing() {
        let store = SettingsStore(url: tempURL())
        XCTAssertEqual(store.load(), Settings.default)
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let store = SettingsStore(url: url)

        var s = Settings.default
        s.managedApps.enabledBundleIDs = ["com.mtkg.clipkun"]
        try store.save(s)

        XCTAssertEqual(store.load(), s)
    }

    func testLoadReturnsDefaultWhenFileCorrupted() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load(), Settings.default)
    }
}
