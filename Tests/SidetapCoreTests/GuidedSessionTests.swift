import XCTest
@testable import SidetapCore

final class GuidedSessionTests: XCTestCase {
    func testCalibrationRequiresTenSamplesInEachOfFourZones() {
        var session = CalibrationSession(draft: CalibrationDraft())

        XCTAssertEqual(session.totalRequired, 40)
        XCTAssertEqual(session.currentZone, .leftTop)

        for zone in DeskZone.allCases {
            for _ in 0..<session.targetPerZone {
                XCTAssertEqual(session.currentZone, zone)
                session.positiveSamples.append(sample(zone: zone, strategy: .passive))
            }
        }

        XCTAssertTrue(session.zonesComplete)
        XCTAssertNil(session.currentZone)
        XCTAssertEqual(session.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(
            DeskZone.allCases.map { session.count(for: $0) },
            Array(repeating: 10, count: 4)
        )
    }

    func testAccuracySessionRequiresFifteenSamplesInEachOfFourZones() {
        var session = EvaluationSession()

        XCTAssertEqual(session.targetPerZone, EvaluationAcceptance.tapsPerZone)
        for zone in DeskZone.allCases {
            for _ in 0..<session.targetPerZone {
                XCTAssertEqual(session.currentZone, zone)
                session.records.append(EvaluationRecord(
                    expectedZone: zone,
                    decision: ClassificationDecision(
                        zone: zone,
                        confidence: 0.9,
                        signalStrength: 0.8,
                        zoneDistances: [],
                        rejectionReason: nil
                    ),
                    responseLatencyMilliseconds: 120
                ))
            }
        }

        XCTAssertNil(session.currentZone)
        XCTAssertEqual(session.records.count, 60)
        XCTAssertEqual(session.progress, 1, accuracy: 0.0001)
    }

    func testSensingComparisonCoversEveryStrategyAndZone() {
        var session = BenchmarkSession()

        for strategy in SensingStrategy.allCases {
            for zone in DeskZone.allCases {
                for _ in 0..<session.targetPerZone {
                    XCTAssertEqual(session.currentStrategy, strategy)
                    XCTAssertEqual(session.currentZone, zone)
                    session.samples.append(BenchmarkSample(
                        labeledTap: sample(zone: zone, strategy: strategy),
                        processingLatencyMilliseconds: 3
                    ))
                }
            }
        }

        XCTAssertNil(session.currentStrategy)
        XCTAssertNil(session.currentZone)
        XCTAssertEqual(session.samples.count, 36)
        XCTAssertEqual(session.progress, 1, accuracy: 0.0001)
    }

    private func sample(zone: DeskZone, strategy: SensingStrategy) -> LabeledTap {
        LabeledTap(
            zone: zone,
            feature: TapFeatureVector(
                strategy: strategy,
                names: ["position"],
                values: [Double(zone.rawValue)],
                quality: SignalQuality(
                    signalToNoiseDB: 24,
                    peakAmplitude: 0.1,
                    rmsAmplitude: 0.02,
                    clippingFraction: 0,
                    noiseFloorRMS: 0.0005,
                    durationMilliseconds: 90
                )
            )
        )
    }
}
