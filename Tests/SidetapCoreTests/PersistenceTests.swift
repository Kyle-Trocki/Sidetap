import XCTest
@testable import SidetapCore

final class PersistenceTests: XCTestCase {
    func testProfileRoundTripDoesNotStoreAudio() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProfileStore(fileURL: url)
        XCTAssertNil(try store.load())

        var profile = SidetapProfile(classifier: try classifier(), maximumTapGap: 0.6)
        profile.setAction(ActionConfiguration(kind: .copyText, text: "Focus mode"), for: .double)
        profile.setAction(
            ActionConfiguration(kind: .openApplication, text: "Notes", bookmarkData: Data([0x48, 0x4F, 0x4C, 0x4F])),
            for: .triple
        )
        try store.save(profile)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.maximumTapGap, 0.6)
        XCTAssertEqual(loaded.classifier.noveltyThreshold, profile.classifier.noveltyThreshold)
        XCTAssertEqual(loaded.classifier.positiveExamples.map(\.values), profile.classifier.positiveExamples.map(\.values))
        XCTAssertEqual(loaded.action(for: .double).kind, .copyText)
        XCTAssertEqual(loaded.action(for: .double).text, "Focus mode")
        XCTAssertEqual(loaded.action(for: .triple).kind, .openApplication)
        XCTAssertEqual(loaded.action(for: .triple).bookmarkData, Data([0x48, 0x4F, 0x4C, 0x4F]))

        let persistedData = try Data(contentsOf: url)
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("\"channels\""))
        XCTAssertFalse(persistedJSON.contains("\"onsetOffset\""))
        XCTAssertFalse(persistedJSON.contains("\"streamSampleIndex\""))
        XCTAssertFalse(persistedData.starts(with: Data("RIFF".utf8)))
    }

    func testGesturesAndTheirActionsRoundTrip() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProfileStore(fileURL: url)

        // Without any actions, a profile has a double and a triple tap that do nothing.
        var profile = SidetapProfile(classifier: try classifier())
        XCTAssertEqual(profile.gestures, [.double, .triple])
        XCTAssertEqual(profile.action(for: .double).kind, ActionKind.none)
        XCTAssertEqual(profile.maximumTapGap, TapGestureCounter.maximumGap)

        profile.setAction(ActionConfiguration(kind: .pasteText), for: .double)
        profile.addGesture()
        profile.addGesture()
        let fiveTaps = try XCTUnwrap(TapGesture(rawValue: 5))
        profile.setAction(ActionConfiguration(kind: .mediaKey), for: fiveTaps)
        try store.save(profile)

        var loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.gestures.map(\.rawValue), [2, 3, 4, 5])
        XCTAssertEqual(loaded.action(for: .double).kind, .pasteText)
        XCTAssertEqual(loaded.action(for: .triple).kind, ActionKind.none)
        XCTAssertEqual(loaded.action(for: fiveTaps).kind, .mediaKey)

        // Removing takes the gesture with the most taps, and never the double or triple tap.
        loaded.removeLastGesture()
        XCTAssertEqual(loaded.gestures.map(\.rawValue), [2, 3, 4])
        loaded.removeLastGesture()
        loaded.removeLastGesture()
        XCTAssertEqual(loaded.gestures, [.double, .triple])
        XCTAssertEqual(loaded.action(for: .double).kind, .pasteText)
    }

    func testFilesFromEarlierVersionsAreSkippedBeforeDecoding() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProfileStore(fileURL: url)

        var earlier = SidetapProfile(classifier: try classifier())
        earlier.version = SidetapProfile.currentVersion - 1
        try store.save(earlier)
        XCTAssertNil(try store.load())

        // A profile from the four-zone calibration no longer matches the current shape at all.
        try Data(#"{"version":3,"name":"Oak desk","zones":[{"zone":0}]}"#.utf8).write(to: url)
        XCTAssertNil(try store.load())
    }

    func testCorruptFileIsReportedInsteadOfSilentlyIgnored() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProfileStore(fileURL: url)
        try Data("{ not valid json".utf8).write(to: url)

        XCTAssertThrowsError(try store.load())
    }

    func testDamagedCalibrationIsReported() throws {
        let damage: [(inout SidetapProfile) -> Void] = [
            { $0.classifier.positiveExamples.removeAll() },
            { $0.classifier.scales[0] = 0 },
            { $0.classifier.negativeExamples = [self.tap(0, names: ["other"])] },
            { $0.maximumTapGap = 0 }
        ]
        for change in damage {
            let url = temporaryFile()
            defer { try? FileManager.default.removeItem(at: url) }
            let store = try ProfileStore(fileURL: url)
            var profile = SidetapProfile(classifier: try classifier())
            change(&profile)
            try store.save(profile)

            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertEqual(error as? ProfileStoreError, .invalidCalibration)
            }
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

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
    }

    /// Trained on two double taps.
    private func classifier() throws -> TrainedTapClassifier {
        try TrainedTapClassifier.train(gestures: [[tap(0), tap(0.01)], [tap(0.02), tap(0.03)]])
    }

    private func tap(_ offset: Double, names: [String] = ["x", "y"]) -> TapFeatureVector {
        TapFeatureVector(
            strategy: .passive,
            names: names,
            values: names.indices.map { Double($0) + offset },
            quality: SignalQuality(
                signalToNoiseDB: 20,
                peakAmplitude: 0.1,
                rmsAmplitude: 0.02,
                clippingFraction: 0,
                noiseFloorRMS: 0.001,
                durationMilliseconds: 90
            )
        )
    }
}
