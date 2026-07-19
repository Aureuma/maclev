import XCTest
@testable import maclev

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testUpdateStartPageNormalizesAndPersists() throws {
        let storageURL = try makeStorageURL()
        let store = SettingsStore(storageURL: storageURL)

        XCTAssertTrue(store.updateStartPage(from: "example.com"))
        XCTAssertEqual(store.startPage, "https://example.com")

        let restored = SettingsStore(storageURL: storageURL)
        XCTAssertEqual(restored.startPage, "https://example.com")
    }

    func testUpdateStartPageRejectsInvalidURLs() throws {
        let storageURL = try makeStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let original = store.startPage

        XCTAssertFalse(store.updateStartPage(from: "javascript:alert('xss')"))
        XCTAssertEqual(store.startPage, original)
    }

    func testRestoreFallsBackToDefaultStartPageWhenPersistedValueIsInvalid() throws {
        let storageURL = try makeStorageURL()
        let invalidState = """
        {
          "startPage": "javascript:alert('xss')",
          "launchFloating": true,
          "defaultCameraPolicy": "ask",
          "defaultMicrophonePolicy": "ask",
          "siteRules": []
        }
        """

        try invalidState.write(to: storageURL, atomically: true, encoding: .utf8)

        let restored = SettingsStore(storageURL: storageURL)
        XCTAssertEqual(restored.startPage, BrowserAddress.defaultStartPage)
    }
}

@MainActor
final class BrowserModelTests: XCTestCase {
    func testWindowModelsKeepIndependentTabState() throws {
        let storageURL = try makeStorageURL()
        let settings = SettingsStore(storageURL: storageURL)
        let firstWindow = BrowserModel(settings: settings)
        let secondWindow = BrowserModel(settings: settings)

        firstWindow.openTab()

        XCTAssertEqual(firstWindow.tabs.count, 2)
        XCTAssertEqual(secondWindow.tabs.count, 1)
        XCTAssertNotEqual(firstWindow.selectedTabID, secondWindow.selectedTabID)
    }

    func testFloatingToggleOnlyAffectsCurrentWindow() throws {
        let storageURL = try makeStorageURL()
        let settings = SettingsStore(storageURL: storageURL)
        settings.launchFloating = true

        let model = BrowserModel(settings: settings)
        model.setFloating(false)

        XCTAssertFalse(model.isFloating)
        XCTAssertTrue(settings.launchFloating)
    }

    func testOpenTabNormalizesPopupAddressAndIssuesLoadCommand() throws {
        let storageURL = try makeStorageURL()
        let settings = SettingsStore(storageURL: storageURL)
        let model = BrowserModel(settings: settings)

        model.openTab(with: "example.com")

        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.tabs.last?.addressText, "https://example.com")
        XCTAssertEqual(model.tabs.last?.command, .load(URL(string: "https://example.com")!))
    }
}

private func makeStorageURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("settings.json")
}
