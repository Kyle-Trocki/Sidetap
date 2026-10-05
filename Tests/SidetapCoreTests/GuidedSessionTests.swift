import XCTest
@testable import SidetapCore

final class GuidedSessionTests: XCTestCase {
    func testCalibrationAsksForDoubleTapsAndThenTripleTaps() {
        var session = CalibrationSession()

        XCTAssertEqual(session.totalRequired, 16)
        for gesture in [TapGesture.double, .triple] {
            for _ in 0..<session.repetitions {
                XCTAssertEqual(session.currentGesture, gesture)
                session.gestures.append(calibrated(gesture, gaps: Array(repeating: 0.25, count: gesture.rawValue - 1)))
            }
        }

        XCTAssertTrue(session.gesturesComplete)
        XCTAssertNil(session.currentGesture)
        XCTAssertEqual(session.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(session.count(for: .double), 8)
        XCTAssertEqual(session.gestures.flatMap(\.taps).count, 40)
    }

    func testAttemptCountsOnlyWithExactlyTheGesturesTapsAllClean() throws {
        var attempt = CalibrationAttempt()

        // One tap of a double tap: the second one was missed.
        attempt.add(tap(), at: 10.0)
        XCTAssertEqual(attempt.result(expecting: .double), .failure(.tapCount(heard: 1, expected: .double)))

        attempt.add(tap(), at: 10.3)
        let doubleTap = try attempt.result(expecting: .double).get()
        XCTAssertEqual(doubleTap.gesture, .double)
        XCTAssertEqual(doubleTap.taps.count, 2)
        XCTAssertEqual(doubleTap.gaps.count, 1)
        XCTAssertEqual(doubleTap.gaps[0], 0.3, accuracy: 0.0001)

        // A third tap is one too many for a double tap. As a triple tap it has
        // the right count, but a tap too soft to learn from spoils it.
        attempt.add(tap(peakAmplitude: 0.001), at: 10.55)
        XCTAssertEqual(attempt.result(expecting: .double), .failure(.tapCount(heard: 3, expected: .double)))
        XCTAssertEqual(attempt.result(expecting: .triple), .failure(.quality(.weak)))
    }

    func testRetryGuidanceSaysWhetherTapsWereMissedOrExtra() {
        XCTAssertTrue(CalibrationRetry.tapCount(heard: 1, expected: .double).guidance.hasPrefix("Heard 1 of 2 taps."))
        XCTAssertTrue(CalibrationRetry.tapCount(heard: 4, expected: .triple).guidance.hasPrefix("Heard 4 taps, and this step needs 3."))
        XCTAssertEqual(CalibrationRetry.quality(.clipped).guidance, GuidedCaptureQualityIssue.clipped.guidance)
    }

    func testLearnedTapGapFollowsTheSlowestCalibratedPaceWithinLimits() {
        var session = CalibrationSession()

        // Nothing calibrated yet, or a quick pace: the default gap.
        XCTAssertEqual(session.maximumTapGap, TapGestureCounter.maximumGap)
        session.gestures = [calibrated(.double, gaps: [0.2]), calibrated(.triple, gaps: [0.25, 0.3])]
        XCTAssertEqual(session.maximumTapGap, TapGestureCounter.maximumGap)

        // A slower pace stretches the gap, with some margin.
        session.gestures.append(calibrated(.double, gaps: [0.5]))
        XCTAssertEqual(session.maximumTapGap, 0.65, accuracy: 0.0001)

        // The gap never passes the longest pause that calibration accepts.
        session.gestures.append(calibrated(.double, gaps: [0.78]))
        XCTAssertEqual(session.maximumTapGap, CalibrationGuidance.longestGap)
    }

    private func calibrated(_ gesture: TapGesture, gaps: [Double]) -> CalibratedGesture {
        CalibratedGesture(gesture: gesture, taps: Array(repeating: tap(), count: gesture.rawValue), gaps: gaps)
    }

    private func tap(peakAmplitude: Double = 0.1) -> TapFeatureVector {
        TapFeatureVector(
            strategy: .passive,
            names: ["signature"],
            values: [1],
            quality: SignalQuality(
                signalToNoiseDB: 24,
                peakAmplitude: peakAmplitude,
                rmsAmplitude: 0.02,
                clippingFraction: 0,
                noiseFloorRMS: 0.0005,
                durationMilliseconds: 90
            )
        )
    }
}
