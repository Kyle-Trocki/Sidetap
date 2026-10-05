import XCTest

final class GuidedNavigationGateTests: XCTestCase {
    func testNoActiveSessionAllowsAllNavigation() {
        XCTAssertNil(GuidedNavigationGate.guidedSection(calibrationActive: false))
        for section in AppSection.allCases {
            XCTAssertTrue(GuidedNavigationGate.canNavigate(to: section, guidedSection: nil))
        }
    }

    func testCalibrationOnlyAllowsItsOwnSection() {
        let guided = GuidedNavigationGate.guidedSection(calibrationActive: true)

        XCTAssertEqual(guided, .calibrate)
        for section in AppSection.allCases {
            XCTAssertEqual(
                GuidedNavigationGate.canNavigate(to: section, guidedSection: guided),
                section == .calibrate
            )
        }
    }
}
