import XCTest
@testable import HoloCore

final class DetectorTests: XCTestCase {
    func testDetectorIgnoresSteadyBackgroundAndFindsImpulse() {
        let sampleRate = 48_000.0
        let detector = StreamingTapDetector(sampleRate: sampleRate, channelCount: 1)
        var events: [DetectedTap] = []

        for _ in 0..<80 {
            events += detector.process(channels: [Array(repeating: 0.0004, count: 512)])
        }
        XCTAssertTrue(events.isEmpty)

        var impulse = Array(repeating: Float(0.0004), count: 512)
        impulse[120] = 0.2
        impulse[121] = -0.13
        events += detector.process(channels: [impulse])
        for _ in 0..<10 {
            events += detector.process(channels: [Array(repeating: 0.0002, count: 512)])
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].channels[0].count, detector.analysisWindowSamples)
        XCTAssertGreaterThan(events[0].onsetOffset, 0)
    }

    func testTapLateInALargeBufferKeepsItsWholeWindow() {
        // macOS delivers 100 ms buffers even when Sidetap requests 512 frames.
        let detector = StreamingTapDetector(sampleRate: 48_000, channelCount: 1, warmUpDuration: 0)
        let onset = 4_500
        var signal = Array(repeating: Float(0.0004), count: 9_600)
        for index in 0..<1_200 {
            let t = Float(index) / 48_000
            signal[onset + index] += 0.2 * exp(-Float(index) / 400) * sin(2 * .pi * 800 * t)
        }

        let events = detector.process(channels: [Array(signal[..<4_800])])
            + detector.process(channels: [Array(signal[4_800...])])

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.onsetOffset, detector.preRollSamples)
        XCTAssertEqual(Double(events.first?.streamSampleIndex ?? 0), Double(onset), accuracy: 24)
    }

    func testTapShortlyAfterRejectedSpeechIsDetected() {
        // Rejected speech from 19 ms, a real tap at 210 ms, in 100 ms buffers.
        let sampleRate = 48_000.0
        let detector = StreamingTapDetector(sampleRate: sampleRate, channelCount: 1, warmUpDuration: 0)
        let speech = candidateSignal(sampleRate: sampleRate, onset: 900, kind: .speech, duration: 0.18)
        let tapOnset = 10_080
        let signal = speech + candidateSignal(sampleRate: sampleRate, onset: tapOnset - speech.count, kind: .tap, duration: 0.2)

        var events: [DetectedTap] = []
        for start in stride(from: 0, to: signal.count, by: 4_800) {
            events += detector.process(channels: [Array(signal[start..<min(start + 4_800, signal.count)])])
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(Double(events.first?.streamSampleIndex ?? 0), Double(tapOnset), accuracy: 48)
    }

    func testDetectorHonorsRefractoryPeriod() {
        let detector = StreamingTapDetector(
            sampleRate: 48_000,
            channelCount: 1,
            analysisDuration: 0.025,
            warmUpDuration: 0
        )
        var chunk = Array(repeating: Float.zero, count: 512)
        chunk[100] = 0.3
        var events: [DetectedTap] = []
        for _ in 0..<4 { events += detector.process(channels: [chunk]) }
        XCTAssertLessThanOrEqual(events.count, 1)
    }

    func testDetectorDoesNotTriggerOnActiveProbe() {
        for sampleRate in [44_100.0, 48_000.0] {
            let detector = StreamingTapDetector(
                sampleRate: sampleRate,
                channelCount: 1,
                warmUpDuration: 0
            )
            let chirp = ActiveProbe.chirp(sampleRate: sampleRate).map { $0 * 0.55 }
            let periodSamples = Int(sampleRate * 0.120)
            var signal: [Float] = []
            for _ in 0..<12 {
                signal.append(contentsOf: chirp)
                signal.append(contentsOf: Array(repeating: 0, count: periodSamples - chirp.count))
            }

            var events: [DetectedTap] = []
            var offset = 0
            while offset < signal.count {
                let end = min(offset + 512, signal.count)
                events += detector.process(channels: [Array(signal[offset..<end])])
                offset = end
            }

            XCTAssertTrue(events.isEmpty, "Probe self-triggered at \(sampleRate) Hz")
        }
    }

    func testDetectorLearnsElevatedBackgroundBeforeEmittingTap() {
        let sampleRate = 48_000.0
        let detector = StreamingTapDetector(sampleRate: sampleRate, channelCount: 1)
        var generator = DeterministicNoise(state: 0x484F4C4F)
        var backgroundEvents: [DetectedTap] = []

        for _ in 0..<120 {
            backgroundEvents += detector.process(channels: [backgroundChunk(generator: &generator)])
        }

        XCTAssertTrue(backgroundEvents.isEmpty, "Steady room noise must not look like repeated taps")
        XCTAssertGreaterThan(detector.noiseFloorRMS, 0.002)

        var tap = backgroundChunk(generator: &generator)
        tap[120] = 0.48
        tap[124] = -0.31
        var tapEvents = detector.process(channels: [tap])
        for _ in 0..<10 {
            tapEvents += detector.process(channels: [backgroundChunk(generator: &generator)])
        }

        XCTAssertEqual(tapEvents.count, 1, "A real impulse must remain detectable above the learned room floor")
    }

    func testImpactGateRejectsPlosiveSpeechButKeepsAResonantTap() {
        let sampleRate = 48_000.0
        let onset = 576
        let speech = DetectedTap(
            channels: [candidateSignal(sampleRate: sampleRate, onset: onset, kind: .speech)],
            onsetOffset: onset,
            streamSampleIndex: 0,
            noiseFloorRMS: 0.001
        )
        let tap = DetectedTap(
            channels: [candidateSignal(sampleRate: sampleRate, onset: onset, kind: .tap)],
            onsetOffset: onset,
            streamSampleIndex: 0,
            noiseFloorRMS: 0.001
        )

        let speechMetrics = ImpactEventGate.metrics(for: speech, sampleRate: sampleRate)
        XCTAssertNotNil(speechMetrics)
        XCTAssertGreaterThan(speechMetrics?.effectiveDurationSeconds ?? 0, 0.04)
        XCTAssertFalse(ImpactEventGate.accepts(speech, sampleRate: sampleRate))
        XCTAssertTrue(ImpactEventGate.accepts(tap, sampleRate: sampleRate))
    }

    func testDetectorDoesNotEmitPlosiveSpeechCandidate() {
        let sampleRate = 48_000.0
        let detector = StreamingTapDetector(
            sampleRate: sampleRate,
            channelCount: 1,
            warmUpDuration: 0
        )
        let signal = candidateSignal(
            sampleRate: sampleRate,
            onset: 900,
            kind: .speech,
            duration: 0.18
        )
        var events: [DetectedTap] = []
        var offset = 0
        while offset < signal.count {
            let end = min(offset + 512, signal.count)
            events += detector.process(channels: [Array(signal[offset..<end])])
            offset = end
        }

        XCTAssertTrue(events.isEmpty, "A plosive followed by voiced energy must not be emitted as a tap")
    }

    private func backgroundChunk(generator: inout DeterministicNoise) -> [Float] {
        var chunk = Array(repeating: Float.zero, count: 512)
        for start in stride(from: 0, to: chunk.count, by: 8) {
            let value = Float((generator.unit() * 2 - 1) * 0.014)
            for index in start..<min(start + 8, chunk.count) {
                chunk[index] = value
            }
        }
        return chunk
    }

    private enum CandidateKind {
        case tap
        case speech
    }

    private func candidateSignal(
        sampleRate: Double,
        onset: Int,
        kind: CandidateKind,
        duration: Double = 0.090
    ) -> [Float] {
        let count = max(Int(sampleRate * duration), onset + 1)
        return (0..<count).map { index in
            let background = 0.0007 * sin(2 * Double.pi * 83 * Double(index) / sampleRate)
            guard index >= onset else { return Float(background) }
            let time = Double(index - onset) / sampleRate
            switch kind {
            case .tap:
                let impact = 0.24 * exp(-time * 2_100) * cos(2 * Double.pi * 1_900 * time)
                let resonance = 0.075 * exp(-time * 24) * sin(2 * Double.pi * 620 * time)
                return Float(background + impact + resonance)
            case .speech:
                let plosive = 0.24 * exp(-time * 850) * sin(2 * Double.pi * 2_700 * time)
                let voiceEnvelope = min(time / 0.010, 1)
                let voiced = 0.075 * voiceEnvelope * (
                    sin(2 * Double.pi * 145 * time)
                        + 0.55 * sin(2 * Double.pi * 290 * time)
                        + 0.30 * sin(2 * Double.pi * 435 * time)
                )
                return Float(background + plosive + voiced)
            }
        }
    }
}

private struct DeterministicNoise {
    var state: UInt64

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}
