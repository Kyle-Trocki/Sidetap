import Foundation

public enum ActiveProbe {
    public static func chirp(
        sampleRate: Double,
        duration: Double = 0.024,
        startFrequency: Double = 15_500,
        endFrequency: Double = 21_000,
        amplitude: Double = 0.035
    ) -> [Float] {
        let count = max(Int(sampleRate * duration), 32)
        return (0..<count).map { index in
            let time = Double(index) / sampleRate
            let slope = (endFrequency - startFrequency) / duration
            let phase = 2 * Double.pi * (startFrequency * time + 0.5 * slope * time * time)
            let edge = min(Double(index) / Double(max(count / 8, 1)), Double(count - 1 - index) / Double(max(count / 8, 1)))
            let envelope = min(max(edge, 0), 1)
            return Float(sin(phase) * amplitude * envelope)
        }
    }

    static func responseFeatures(
        signal: [Double],
        sampleRate: Double,
        spectrum: [Double]? = nil
    ) -> (names: [String], values: [Double]) {
        let probe = chirp(sampleRate: sampleRate).map(Double.init)
        guard signal.count >= probe.count else {
            return (activeFeatureNames, Array(repeating: 0, count: activeFeatureNames.count))
        }

        let stride = max(probe.count / 4, 1)
        var correlations: [Double] = []
        var index = 0
        let probeEnergy = sqrt(probe.reduce(0) { $0 + $1 * $1 }) + 1e-12
        while index + probe.count <= signal.count {
            var dot = 0.0
            var energy = 0.0
            for probeIndex in probe.indices {
                let sample = signal[index + probeIndex]
                dot += sample * probe[probeIndex]
                energy += sample * sample
            }
            correlations.append(dot / (probeEnergy * sqrt(energy) + 1e-12))
            index += stride
        }

        let peak = correlations.map(abs).max() ?? 0
        let peakIndex = correlations.enumerated().max(by: { abs($0.element) < abs($1.element) })?.offset ?? 0
        let mean = correlations.isEmpty ? 0 : correlations.reduce(0, +) / Double(correlations.count)
        let variance = correlations.isEmpty ? 0 : correlations.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(correlations.count)
        let responseSpectrum = spectrum ?? Radix2FFT.powerSpectrum(
            signal,
            size: min(Radix2FFT.nextPowerOfTwo(signal.count), 4096)
        )
        let responseBands = normalizedLogBands(spectrum: responseSpectrum, sampleRate: sampleRate, count: 8)
        let values = [peak, Double(peakIndex) / Double(max(correlations.count - 1, 1)), mean, sqrt(variance)] + responseBands
        return (activeFeatureNames, values)
    }

    static let activeFeatureNames = [
        "probe_correlation_peak", "probe_correlation_lag", "probe_correlation_mean", "probe_correlation_spread"
    ] + (0..<8).map { "probe_band_\($0)" }

    private static func normalizedLogBands(spectrum: [Double], sampleRate: Double, count: Int) -> [Double] {
        let minimum = 8_000.0
        let maximum = min(sampleRate * 0.48, 22_000)
        let total = spectrum.reduce(0, +) + 1e-15
        return (0..<count).map { band in
            let lowRatio = Double(band) / Double(count)
            let highRatio = Double(band + 1) / Double(count)
            let low = minimum * pow(maximum / minimum, lowRatio)
            let high = minimum * pow(maximum / minimum, highRatio)
            let start = max(Int(low / sampleRate * Double((spectrum.count - 1) * 2)), 0)
            let end = min(Int(high / sampleRate * Double((spectrum.count - 1) * 2)), spectrum.count - 1)
            guard end >= start else { return -30 }
            let energy = spectrum[start...end].reduce(0, +) / total
            return log10(energy + 1e-12)
        }
    }
}
