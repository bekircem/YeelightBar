import XCTest
@testable import YeelightBar

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testSettingsSidebarContainsEveryTopLevelPanel() {
        XCTAssertEqual(SettingsPanel.allCases.count, 9)
        XCTAssertEqual(Set(SettingsPanel.allCases.map(\.rawValue)).count, 9)
        XCTAssertGreaterThanOrEqual(SettingsLayout.sidebarWidth, 200)
        XCTAssertLessThanOrEqual(SettingsLayout.sidebarWidth, 240)
        XCTAssertGreaterThanOrEqual(SettingsLayout.sidebarIconWidth, 16)
        XCTAssertLessThanOrEqual(SettingsLayout.sidebarIconWidth, 20)
    }

    func testEverySettingsPanelRoundTripsThroughStoredSelection() {
        for panel in SettingsPanel.allCases {
            let storedValue = SettingsSelection.rawValue(for: panel)

            XCTAssertEqual(SettingsSelection.panel(for: storedValue), panel)
        }
    }

    func testMissingOrInvalidSelectionFallsBackToGeneral() {
        XCTAssertEqual(SettingsSelection.rawValue(for: nil), SettingsPanel.general.rawValue)
        XCTAssertEqual(SettingsSelection.panel(for: "removed-panel"), .general)
    }
}
