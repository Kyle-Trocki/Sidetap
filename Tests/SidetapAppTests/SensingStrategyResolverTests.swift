import SidetapCore
import XCTest

final class SensingStrategyResolverTests: XCTestCase {
    func testCalibrationDraftWinsOverProfile() {
        XCTAssertEqual(SensingStrategyResolver.resolve(calibration: .hybrid, profile: .passive), .hybrid)
    }

    func testProfileAppliesWithoutACalibration() {
        XCTAssertEqual(SensingStrategyResolver.resolve(calibration: nil, profile: .active), .active)
    }

    func testDefaultsToPassive() {
        XCTAssertEqual(SensingStrategyResolver.resolve(calibration: nil, profile: nil), .passive)
    }
}
