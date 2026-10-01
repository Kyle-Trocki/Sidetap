import XCTest
@testable import SidetapCore

final class ActiveProbeTests: XCTestCase {
    func testChirpIsBoundedAndFaded() {
        let chirp = ActiveProbe.chirp(sampleRate: 48_000)
        XCTAssertGreaterThan(chirp.count, 1_000)
        XCTAssertLessThanOrEqual(chirp.map { abs($0) }.max() ?? 1, 0.036)
        XCTAssertEqual(chirp.first ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(chirp.last ?? 1, 0, accuracy: 0.001)
    }

    func testResponseFeaturesRecoverInjectedProbeAndDelay() throws {
        let sampleRate = 48_000.0
        let probe = ActiveProbe.chirp(sampleRate: sampleRate).map(Double.init)
        let offset = probe.count
        var signal = Array(repeating: 0.0, count: 4_320)
        for index in probe.indices {
            signal[offset + index] = probe[index]
        }

        let response = ActiveProbe.responseFeatures(signal: signal, sampleRate: sampleRate)
        let peakIndex = try XCTUnwrap(response.names.firstIndex(of: "probe_correlation_peak"))
        let lagIndex = try XCTUnwrap(response.names.firstIndex(of: "probe_correlation_lag"))

        XCTAssertGreaterThan(response.values[peakIndex], 0.95)
        XCTAssertGreaterThan(response.values[lagIndex], 0.15)
        XCTAssertLessThan(response.values[lagIndex], 0.5)
        XCTAssertTrue(response.values.allSatisfy(\.isFinite))
    }
}
