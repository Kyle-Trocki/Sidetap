import Foundation

/// Sidebar gating for guided captures: while a calibration is running, only
/// its section is reachable.
enum GuidedNavigationGate {
    static func guidedSection(calibrationActive: Bool) -> AppSection? {
        calibrationActive ? .calibrate : nil
    }

    static func canNavigate(to candidate: AppSection, guidedSection: AppSection?) -> Bool {
        guidedSection == nil || guidedSection == candidate
    }
}
