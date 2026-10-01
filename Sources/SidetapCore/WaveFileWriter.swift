import Foundation

public enum WaveFileWriter {
    /// Writes non-interleaved normalized Float32 channels as an IEEE-float WAV file.
    public static func write(channels: [[Float]], sampleRate: Double, to url: URL) throws {
        guard let frameCount = channels.map(\.count).min(), frameCount > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let channelCount = max(channels.count, 1)
        let bytesPerSample = 4
        let dataByteCount = frameCount * channelCount * bytesPerSample
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(3)) // IEEE float
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate.rounded()))
        data.appendLittleEndian(UInt32(sampleRate.rounded()) * UInt32(channelCount * bytesPerSample))
        data.appendLittleEndian(UInt16(channelCount * bytesPerSample))
        data.appendLittleEndian(UInt16(32))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(dataByteCount))

        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                data.appendLittleEndian(channels[channel][frame].bitPattern)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
