import CoreLocation
import XCTest
@testable import SidetapCore

final class PersistenceTests: XCTestCase {
    func testProfileRoundTripDoesNotStoreAudio() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var zones = DeskZone.allCases.map { ZoneConfiguration(zone: $0) }
        zones[DeskZone.leftTop.rawValue].action = ZoneActionConfiguration(
            kind: .copyText,
            text: "Focus mode"
        )
        zones[DeskZone.rightBottom.rawValue].action = ZoneActionConfiguration(
            kind: .openApplication,
            text: "Notes",
            bookmarkData: Data([0x48, 0x4F, 0x4C, 0x4F])
        )
        let profile = SidetapProfile(
            name: "Oak desk",
            surfaceDescription: "Solid oak",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            ),
            zones: zones
        )
        try store.save(profile)
        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.id, profile.id)
        XCTAssertEqual(loaded.name, "Oak desk")
        XCTAssertEqual(loaded.zones.map(\.zone), DeskZone.allCases)
        XCTAssertEqual(loaded.action(for: .leftTop).kind, .copyText)
        XCTAssertEqual(loaded.action(for: .leftTop).text, "Focus mode")
        XCTAssertEqual(loaded.action(for: .rightBottom).kind, .openApplication)
        XCTAssertEqual(loaded.action(for: .rightBottom).bookmarkData, Data([0x48, 0x4F, 0x4C, 0x4F]))

        let files = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.pathExtension, "json")

        let persistedURL = try XCTUnwrap(files.first)
        let persistedData = try Data(contentsOf: persistedURL)
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("\"channels\""))
        XCTAssertFalse(persistedJSON.contains("\"onsetOffset\""))
        XCTAssertFalse(persistedJSON.contains("\"streamSampleIndex\""))
        XCTAssertFalse(persistedData.starts(with: Data("RIFF".utf8)))
    }

    func testPinnedLocationRoundTripsAndSelectsNearestDesk() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        func profile(_ name: String, _ location: ProfileLocation?) -> SidetapProfile {
            var profile = SidetapProfile(
                name: name,
                surfaceDescription: "Oak",
                laptopPositionNote: "Centered",
                classifier: classifier,
                calibration: CalibrationSummary(
                    sampleCount: DeskZone.allCases.count * 2,
                    samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                    leaveOneOutAccuracy: 1
                )
            )
            profile.location = location
            return profile
        }
        let home = profile("Home", ProfileLocation(latitude: 40.7484, longitude: -73.9857))
        let work = profile("Work", ProfileLocation(latitude: 40.7061, longitude: -74.0087))
        let unpinned = profile("Travel", nil)
        try [home, work, unpinned].forEach(store.save)

        var withGesture = home
        withGesture.setAction(ZoneActionConfiguration(kind: .pasteText), for: .double)
        withGesture.addGesture()
        withGesture.addGesture()
        let fiveTaps = try XCTUnwrap(TapGesture(rawValue: 5))
        withGesture.setAction(ZoneActionConfiguration(kind: .mediaKey), for: fiveTaps)
        try store.save(withGesture)

        let loaded = try store.loadAll()
        // A saved gesture action comes back; a profile saved without one has no action.
        XCTAssertEqual(loaded.first { $0.id == home.id }?.action(for: .double).kind, .pasteText)
        XCTAssertEqual(loaded.first { $0.id == home.id }?.action(for: .triple).kind, ZoneActionKind.none)
        XCTAssertEqual(loaded.first { $0.id == work.id }?.action(for: .double).kind, ZoneActionKind.none)
        // Added gestures come back too. A profile without any has a double and a triple tap.
        var reloaded = try XCTUnwrap(loaded.first { $0.id == home.id })
        XCTAssertEqual(reloaded.gestures.map(\.rawValue), [2, 3, 4, 5])
        XCTAssertEqual(reloaded.action(for: fiveTaps).kind, .mediaKey)
        reloaded.removeLastGesture()
        XCTAssertEqual(reloaded.gestures.map(\.rawValue), [2, 3, 4])
        XCTAssertEqual(loaded.first { $0.id == work.id }?.gestures, [.double, .triple])
        XCTAssertEqual(loaded.first { $0.id == home.id }?.location, home.location)
        XCTAssertNil(loaded.first { $0.id == unpinned.id }?.location)

        // About 50 m from each desk, then more than 5 km from both.
        XCTAssertEqual(loaded.nearest(to: CLLocation(latitude: 40.7488, longitude: -73.9855))?.id, home.id)
        XCTAssertEqual(loaded.nearest(to: CLLocation(latitude: 40.7064, longitude: -74.0090))?.id, work.id)
        XCTAssertNil(loaded.nearest(to: CLLocation(latitude: 40.7900, longitude: -73.9500)))
    }

    func testLegacySixZoneProfileIsIgnoredBeforeZoneDecoding() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = SidetapProfile(
            name: "Legacy desk",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: nil
            )
        )
        profile.version = SidetapProfile.currentVersion - 1

        try store.save(profile)

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testLegacyNineZoneValuesAreSkippedBeforeCurrentEnumDecoding() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let legacy = temporary.appendingPathComponent("legacy-nine-zone.json")
        try Data(#"{"version":1,"zones":[{"zone":8}]}"#.utf8).write(to: legacy)

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testCorruptProfileIsReportedInsteadOfSilentlyIgnored() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let corrupt = temporary.appendingPathComponent("corrupt.json")
        try Data("{ not valid json".utf8).write(to: corrupt)

        XCTAssertThrowsError(try store.loadAll())
    }

    func testCurrentProfileWithMissingZoneIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = SidetapProfile(
            name: "Incomplete desk",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        profile.zones.removeLast()
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentTopology("\(profile.id.uuidString).json")
            )
        }
    }

    func testCurrentProfileWithIncompleteClassifierIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = SidetapProfile(
            name: "Damaged classifier",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        profile.classifier.positiveExamples.removeAll { $0.zone == .rightBottom }
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentClassifier("\(profile.id.uuidString).json")
            )
        }
    }

    func testCurrentProfileWithMismatchedCalibrationSummaryIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        let profile = SidetapProfile(
            name: "Damaged summary",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2 + 1,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentCalibration("\(profile.id.uuidString).json")
            )
        }
    }

    func testWaveWriterProducesFloatWAVHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try WaveFileWriter.write(channels: [[0, 0.25, -0.25]], sampleRate: 48_000, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(data.count, 44 + 3 * 4)
    }

    func testEvaluationStoreRoundTripsJSONAndCSV() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try EvaluationStore(directory: temporary)
        let profileID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let decision = ClassificationDecision(
            zone: .rightBottom,
            confidence: 0.88,
            signalStrength: 0.72,
            zoneDistances: [],
            rejectionReason: nil
        )
        let report = EvaluationReport(
            profileID: profileID,
            profileName: "Oak",
            strategy: .passive,
            startedAt: timestamp.addingTimeInterval(-10),
            completedAt: timestamp,
            records: [EvaluationRecord(
                expectedZone: .rightBottom,
                decision: decision,
                responseLatencyMilliseconds: 123,
                capturedAt: timestamp
            )]
        )

        let jsonURL = try store.save(report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: jsonURL.deletingPathExtension().appendingPathExtension("csv").path
        ))

        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.profileID, profileID)
        XCTAssertEqual(loaded.profileName, "Oak")
        XCTAssertEqual(loaded.topologyZoneCount, DeskZone.allCases.count)
        XCTAssertEqual(loaded.records.count, 1)
        XCTAssertEqual(loaded.records.first?.predictedZone, .rightBottom)
        XCTAssertEqual(loaded.records.first?.responseLatencyMilliseconds, 123)
    }

    func testEvaluationStoreSkipsReportsFromOlderTopologies() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try EvaluationStore(directory: temporary)
        let oldReport = EvaluationReport(
            topologyZoneCount: 6,
            profileName: "Old six-zone desk",
            strategy: .passive,
            startedAt: Date(),
            records: []
        )
        try oldReport.jsonData().write(to: temporary.appendingPathComponent("old.json"))

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testApproachComparisonRejectsObsoleteTopology() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ApproachComparisonStore(fileURL: url)
        let score = ApproachScore(
            strategy: .passive,
            crossValidationAccuracy: 0.8,
            rejectionRate: 0.1,
            medianProcessingLatencyMilliseconds: 3,
            sampleCount: 18
        )

        try store.save(ApproachComparison(
            scores: [score],
            selectedStrategy: .passive,
            measuredAt: Date(),
            topologyZoneCount: 9
        ))
        XCTAssertNil(try store.load())

        let profileID = UUID()
        let current = ApproachComparison(
            scores: [score],
            selectedStrategy: .passive,
            measuredAt: Date(),
            profileID: profileID
        )
        try store.save(current)
        XCTAssertEqual(try store.load()?.topologyZoneCount, DeskZone.allCases.count)
        XCTAssertEqual(try store.load()?.profileID, profileID)
    }

    private func samples() -> [LabeledTap] {
        DeskZone.allCases.flatMap { zone in
            (0..<2).map { index in
                LabeledTap(
                    zone: zone,
                    feature: TapFeatureVector(
                        strategy: .passive,
                        names: ["x", "y"],
                        values: [Double(zone.row) + Double(index) * 0.01, Double(zone.column) - Double(index) * 0.01],
                        quality: SignalQuality(
                            signalToNoiseDB: 20,
                            peakAmplitude: 0.1,
                            rmsAmplitude: 0.02,
                            clippingFraction: 0,
                            noiseFloorRMS: 0.001,
                            durationMilliseconds: 90
                        )
                    )
                )
            }
        }
    }
}
