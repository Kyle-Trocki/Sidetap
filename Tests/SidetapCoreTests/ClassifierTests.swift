import XCTest
@testable import SidetapCore

final class ClassifierTests: XCTestCase {
    func testClassifierAcceptsTapsLikeTheCalibratedOnes() throws {
        let classifier = try TrainedTapClassifier.train(gestures: calibratedGestures())

        let decision = classifier.predict(tap(jitter: 0.015))

        XCTAssertTrue(decision.isTap)
        XCTAssertNil(decision.rejectionReason)
        XCTAssertGreaterThan(decision.confidence, 0.4)
    }

    func testClassifierRejectsWeakAndOutOfDistributionSignals() throws {
        let classifier = try TrainedTapClassifier.train(gestures: calibratedGestures())
        var weak = tap()
        weak.quality.peakAmplitude = 0.001
        XCTAssertEqual(classifier.predict(weak).rejectionReason, .weakSignal)

        var alien = tap()
        alien.values = [100, -100, 80, -70]
        XCTAssertEqual(classifier.predict(alien).rejectionReason, .outOfDistribution)
        XCTAssertFalse(classifier.predict(alien).isTap)
    }

    func testClassifierRejectsClippedAndNoisySignalsBeforeDistanceMatching() throws {
        let classifier = try TrainedTapClassifier.train(gestures: calibratedGestures())

        var clipped = tap()
        clipped.quality.clippingFraction = SignalQuality.maximumReliableClippingFraction + 0.01
        clipped.quality.peakAmplitude = 0.001
        XCTAssertEqual(classifier.predict(clipped).rejectionReason, .clippedSignal)

        var noisy = tap()
        noisy.quality.signalToNoiseDB = SignalQuality.minimumClassificationSignalToNoiseDB - 0.1
        XCTAssertEqual(classifier.predict(noisy).rejectionReason, .lowSignalToNoise)
    }

    func testSchemaMismatchIsRejected() throws {
        let classifier = try TrainedTapClassifier.train(gestures: calibratedGestures())
        var mismatched = tap()
        mismatched.names[0] = "other"
        XCTAssertEqual(classifier.predict(mismatched).rejectionReason, .schemaMismatch)
    }

    func testClassifierRejectsCalibratedNegativeExample() throws {
        let typing = tap(jitter: 0.042)
        // Without the negative example, the same sound passes as a tap.
        XCTAssertTrue(try TrainedTapClassifier.train(gestures: calibratedGestures()).predict(typing).isTap)

        let classifier = try TrainedTapClassifier.train(gestures: calibratedGestures(), negativeExamples: [typing])

        XCTAssertEqual(classifier.predict(typing).rejectionReason, .resemblesNegativeExample)
    }

    func testNoveltyThresholdMeasuresVariationBetweenGesturesNotWithinOne() throws {
        // Both taps of each double tap are identical, and the gestures differ.
        let gestures = [0.0, 1, 2, 3].map { value in
            [oneDimensionFeature(value), oneDimensionFeature(value)]
        }
        let classifier = try TrainedTapClassifier.train(gestures: gestures)

        // Measured within a gesture, taps would look identical and the threshold
        // would fall to its floor, which rejects a tap this far from the others.
        XCTAssertGreaterThan(classifier.noveltyThreshold, 0.95)
        XCTAssertTrue(classifier.predict(oneDimensionFeature(5)).isTap)
        XCTAssertEqual(classifier.predict(oneDimensionFeature(9)).rejectionReason, .outOfDistribution)
    }

    func testTrainingNeedsTwoGesturesWithOneFeatureSchema() {
        XCTAssertThrowsError(try TrainedTapClassifier.train(gestures: [[tap(), tap()]])) { error in
            XCTAssertEqual(error as? ClassifierTrainingError, .notEnoughSamples)
        }
        XCTAssertThrowsError(try TrainedTapClassifier.train(gestures: [[tap()], [oneDimensionFeature(1)]])) { error in
            XCTAssertEqual(error as? ClassifierTrainingError, .inconsistentFeatures)
        }
    }

    func testTapGestureCounterGroupsTapsByGap() {
        var counter = TapGestureCounter()

        // Three taps 0.25 s apart are one gesture of three.
        XCTAssertEqual(counter.add(at: 10.00), 1)
        XCTAssertEqual(counter.add(at: 10.25), 2)
        XCTAssertEqual(counter.add(at: 10.50), 3)
        XCTAssertEqual(counter.finish(), 3)

        // A pause longer than the gap starts a new gesture, and finishing resets the count.
        XCTAssertEqual(counter.add(at: 20.0), 1)
        XCTAssertEqual(counter.add(at: 20.3), 2)
        XCTAssertEqual(counter.add(at: 21.0), 1)
        XCTAssertEqual(counter.finish(), 1)
        XCTAssertEqual(counter.add(at: 21.2), 1)

        // A profile that learned a slower pace keeps the same pause in one gesture.
        XCTAssertEqual(counter.add(at: 21.9, maximumGap: 0.8), 2)

        XCTAssertEqual(TapGesture(rawValue: 2), .double)
        XCTAssertNil(TapGesture(rawValue: 1))
        XCTAssertEqual(TapGesture(rawValue: 5)?.displayName, "5 taps")
    }

    /// Eight double taps and eight triple taps, as calibration collects them.
    private func calibratedGestures() -> [[TapFeatureVector]] {
        CalibrationGuidance.gestures.flatMap { gesture in
            (0..<CalibrationGuidance.repetitionsPerGesture).map { repetition in
                (0..<gesture.rawValue).map { index in
                    tap(jitter: Double(repetition * 3 + index - 12) * 0.004)
                }
            }
        }
    }

    private func tap(jitter: Double = 0) -> TapFeatureVector {
        TapFeatureVector(
            strategy: .passive,
            names: ["attack", "ring", "brightness", "texture"],
            values: [2.2 + jitter, 2.0 - jitter, 1.6 + jitter * 0.5, 1.05 - jitter * 0.2],
            quality: cleanQuality
        )
    }

    private func oneDimensionFeature(_ value: Double) -> TapFeatureVector {
        TapFeatureVector(strategy: .passive, names: ["signature"], values: [value], quality: cleanQuality)
    }

    private var cleanQuality: SignalQuality {
        SignalQuality(
            signalToNoiseDB: 28,
            peakAmplitude: 0.12,
            rmsAmplitude: 0.025,
            clippingFraction: 0,
            noiseFloorRMS: 0.0004,
            durationMilliseconds: 90
        )
    }
}
