import Foundation

public struct SignalQuality: Codable, Equatable, Sendable {
    public static let minimumReliablePeakAmplitude = 0.003
    public static let maximumReliableClippingFraction = 0.20
    public static let minimumClassificationSignalToNoiseDB = 6.0
    /// Above this room level, Sidetap runs no actions rather than guess through
    /// the noise. Measured on a MacBook Pro's built-in microphone: quiet rooms
    /// sat at 0.0005 to 0.0017, and a room with music and talking at a median
    /// of 0.0053. At 0.005 only the louder half of that room is blocked; lower
    /// it toward 0.002 to block all of it.
    public static let maximumRoomNoiseFloorRMS = 0.005

    public var signalToNoiseDB: Double
    public var peakAmplitude: Double
    public var rmsAmplitude: Double
    public var clippingFraction: Double
    public var noiseFloorRMS: Double
    public var durationMilliseconds: Double

    public init(
        signalToNoiseDB: Double,
        peakAmplitude: Double,
        rmsAmplitude: Double,
        clippingFraction: Double,
        noiseFloorRMS: Double,
        durationMilliseconds: Double
    ) {
        self.signalToNoiseDB = signalToNoiseDB
        self.peakAmplitude = peakAmplitude
        self.rmsAmplitude = rmsAmplitude
        self.clippingFraction = clippingFraction
        self.noiseFloorRMS = noiseFloorRMS
        self.durationMilliseconds = durationMilliseconds
    }

    public var score: Double {
        let snr = min(max((signalToNoiseDB - 4) / 30, 0), 1)
        let strength = min(max((peakAmplitude - Self.minimumReliablePeakAmplitude) / 0.15, 0), 1)
        let clean = 1 - min(clippingFraction * 4, 1)
        return 0.55 * snr + 0.25 * strength + 0.20 * clean
    }

    public var summary: String {
        if clippingFraction > Self.maximumReliableClippingFraction { return "Clipped" }
        if peakAmplitude < Self.minimumReliablePeakAmplitude { return "Weak" }
        if signalToNoiseDB < Self.minimumClassificationSignalToNoiseDB { return "Noisy" }
        if score > 0.72 { return "Excellent" }
        if score > 0.48 { return "Good" }
        return "Fair"
    }
}

public struct TapFeatureVector: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var version: Int
    public var strategy: SensingStrategy
    public var names: [String]
    public var values: [Double]
    public var quality: SignalQuality
    public var capturedAt: Date

    public init(
        strategy: SensingStrategy,
        names: [String],
        values: [Double],
        quality: SignalQuality,
        capturedAt: Date = Date()
    ) {
        self.version = Self.schemaVersion
        self.strategy = strategy
        self.names = names
        self.values = values
        self.quality = quality
        self.capturedAt = capturedAt
    }
}

public enum SensingStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    case passive
    case active
    case hybrid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .passive: return "Passive tap acoustics"
        case .active: return "Active acoustic probe"
        case .hybrid: return "Hybrid"
        }
    }

    public var detail: String {
        switch self {
        case .passive:
            return "Uses only the sound and vibration produced by a tap."
        case .active:
            return "Measures how a quiet repeating chirp changes around a tap."
        case .hybrid:
            return "Combines tap acoustics with the chirp response."
        }
    }
}

public enum RejectionReason: String, Codable, Sendable, Equatable {
    case weakSignal
    case lowSignalToNoise
    case clippedSignal
    case outOfDistribution
    case resemblesNegativeExample
    case schemaMismatch
    case paused

    public var displayName: String {
        switch self {
        case .weakSignal: return "Signal too weak"
        case .lowSignalToNoise: return "Background noise too high"
        case .clippedSignal: return "Signal clipped"
        case .outOfDistribution: return "Unlike calibrated taps"
        case .resemblesNegativeExample: return "Recognized as a sound to reject"
        case .schemaMismatch: return "Profile is incompatible"
        case .paused: return "Listening paused"
        }
    }
}

/// Counts taps into a gesture. Taps no more than the maximum gap apart belong
/// to the same gesture; a longer pause starts a new one.
public struct TapGestureCounter: Sendable {
    /// The default maximum gap, in seconds. Measured on real double and triple
    /// taps: 0.19 to 0.34 s between taps. A profile can learn a longer one.
    public static let maximumGap = 0.45

    private var count = 0
    private var lastTap = -Double.infinity

    public init() {}

    /// Registers a tap and returns how many taps the gesture has so far.
    public mutating func add(at time: Double, maximumGap: Double = Self.maximumGap) -> Int {
        count = time - lastTap <= maximumGap ? count + 1 : 1
        lastTap = time
        return count
    }

    /// Ends the gesture and returns its tap count.
    public mutating func finish() -> Int {
        defer {
            count = 0
            lastTap = -.infinity
        }
        return count
    }
}

public struct DetectedTap: Sendable {
    public var channels: [[Float]]
    public var onsetOffset: Int
    public var streamSampleIndex: Int64
    public var noiseFloorRMS: Double

    public init(
        channels: [[Float]],
        onsetOffset: Int,
        streamSampleIndex: Int64,
        noiseFloorRMS: Double
    ) {
        self.channels = channels
        self.onsetOffset = onsetOffset
        self.streamSampleIndex = streamSampleIndex
        self.noiseFloorRMS = noiseFloorRMS
    }
}

public struct SpectrumBand: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { Int(centerFrequency.rounded()) }
    public var centerFrequency: Double
    public var levelDB: Double

    public init(centerFrequency: Double, levelDB: Double) {
        self.centerFrequency = centerFrequency
        self.levelDB = levelDB
    }
}
