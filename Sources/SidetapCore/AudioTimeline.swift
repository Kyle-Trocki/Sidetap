import Foundation

public enum AudioTimeline {
    public static let invalidElapsedMilliseconds = -1.0

    /// Maps an event's absolute stream sample index onto the host clock of a captured buffer.
    /// The event can begin in the current buffer or in an earlier buffer while its window finishes.
    public static func eventHostTimeSeconds(
        bufferStartHostTimeSeconds: Double,
        bufferStartSampleIndex: Int64,
        eventSampleIndex: Int64,
        sampleRate: Double
    ) -> Double {
        guard bufferStartHostTimeSeconds.isFinite, sampleRate.isFinite, sampleRate > 0 else {
            return bufferStartHostTimeSeconds.isFinite ? bufferStartHostTimeSeconds : 0
        }
        let sampleOffset = eventSampleIndex - bufferStartSampleIndex
        return bufferStartHostTimeSeconds + Double(sampleOffset) / sampleRate
    }

    public static func elapsedMilliseconds(
        since eventHostTimeSeconds: Double,
        now nowHostTimeSeconds: Double
    ) -> Double {
        guard eventHostTimeSeconds.isFinite,
              nowHostTimeSeconds.isFinite,
              nowHostTimeSeconds >= eventHostTimeSeconds else {
            return invalidElapsedMilliseconds
        }
        return (nowHostTimeSeconds - eventHostTimeSeconds) * 1_000
    }
}
