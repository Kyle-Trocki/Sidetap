import XCTest
@testable import SidetapCore

final class AudioTimelineTests: XCTestCase {
    func testMapsCurrentBufferEventOntoHostClock() {
        let time = AudioTimeline.eventHostTimeSeconds(
            bufferStartHostTimeSeconds: 1_000,
            bufferStartSampleIndex: 48_000,
            eventSampleIndex: 48_480,
            sampleRate: 48_000
        )

        XCTAssertEqual(time, 1_000.010, accuracy: 1e-9)
    }

    func testMapsEarlierCaptureOnsetFromFinishingBuffer() {
        let time = AudioTimeline.eventHostTimeSeconds(
            bufferStartHostTimeSeconds: 1_000,
            bufferStartSampleIndex: 96_000,
            eventSampleIndex: 93_600,
            sampleRate: 48_000
        )

        XCTAssertEqual(time, 999.950, accuracy: 1e-9)
    }

    func testInvalidRateFallsBackToBufferTime() {
        XCTAssertEqual(
            AudioTimeline.eventHostTimeSeconds(
                bufferStartHostTimeSeconds: 42,
                bufferStartSampleIndex: 0,
                eventSampleIndex: 1,
                sampleRate: 0
            ),
            42
        )
    }

    func testElapsedLatencyRejectsClockAnomalies() {
        XCTAssertEqual(
            AudioTimeline.elapsedMilliseconds(since: 10, now: 10.125),
            125,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            AudioTimeline.elapsedMilliseconds(since: 11, now: 10),
            AudioTimeline.invalidElapsedMilliseconds
        )
        XCTAssertEqual(
            AudioTimeline.elapsedMilliseconds(since: .nan, now: 10),
            AudioTimeline.invalidElapsedMilliseconds
        )
    }
}
