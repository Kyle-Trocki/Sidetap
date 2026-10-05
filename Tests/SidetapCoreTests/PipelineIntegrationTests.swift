import XCTest
@testable import SidetapCore

final class PipelineIntegrationTests: XCTestCase {
    func testStreamingDetectorThroughClassifierAcceptsTapsAndRejectsOtherImpacts() throws {
        // Eight double taps, each tap run through the detector and feature extractor.
        let gestures = try (0..<8).map { gesture in
            try (0..<2).map { tap in
                try detectedFeature(frequency: 470 * (1 + Double(gesture * 2 + tap - 8) * 0.002))
            }
        }
        let classifier = try TrainedTapClassifier.train(gestures: gestures)

        let heldOut = classifier.predict(try detectedFeature(frequency: 470 * 1.001))
        XCTAssertTrue(heldOut.isTap, "A held-out tap was rejected: \(String(describing: heldOut.rejectionReason))")

        // An impact with a very different resonance still gets past the detector,
        // but it isn't one of the calibrated taps.
        let other = classifier.predict(try detectedFeature(frequency: 2_300))
        XCTAssertEqual(other.rejectionReason, .outOfDistribution)
    }

    private func detectedFeature(frequency: Double) throws -> TapFeatureVector {
        let sampleRate = 48_000.0
        let detector = StreamingTapDetector(
            sampleRate: sampleRate,
            channelCount: 1,
            warmUpDuration: 0
        )
        let extractor = TapFeatureExtractor(sampleRate: sampleRate, strategy: .passive)
        let totalSamples = Int(sampleRate * 0.14)
        let onset = 1_100
        let signal: [Float] = (0..<totalSamples).map { index in
            guard index >= onset else { return 0.0002 }
            let time = Double(index - onset) / sampleRate
            // A surface tap begins with a brief impact burst before its longer
            // resonance. An abruptly started sustained tone without the burst
            // is intentionally rejected by the detector.
            let impact = 0.48 * exp(-time * 2_500) * cos(2 * Double.pi * 1_800 * time)
            let envelope = exp(-time * 48)
            let fundamental = sin(2 * Double.pi * frequency * time)
            let overtone = 0.24 * sin(2 * Double.pi * frequency * 2.1 * time)
            return Float(impact + 0.13 * envelope * (fundamental + overtone))
        }

        var events: [DetectedTap] = []
        var offset = 0
        while offset < signal.count {
            let end = min(offset + 512, signal.count)
            events += detector.process(channels: [Array(signal[offset..<end])])
            offset = end
        }

        let event = try XCTUnwrap(events.first, "Detector missed the \(frequency) Hz tap")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.channels.first?.count, detector.analysisWindowSamples)
        return extractor.extract(from: event)
    }
}
