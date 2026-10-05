import Foundation

public enum CalibrationGuidance {
    /// The gestures that calibration asks for, in order. Every other gesture
    /// reuses what these two teach: the sound of a tap and the pace between taps.
    public static let gestures: [TapGesture] = [.double, .triple]

    /// How many times each gesture is performed. Eight double taps and eight
    /// triple taps give 40 taps.
    public static let repetitionsPerGesture = 8

    /// The longest pause between taps that calibration accepts and that a
    /// profile can learn, in seconds.
    public static let longestGap = 0.8
}

/// One accepted calibration gesture: its taps and the pauses between them.
public struct CalibratedGesture: Equatable, Sendable {
    public var gesture: TapGesture
    public var taps: [TapFeatureVector]
    /// Seconds between each tap and the next.
    public var gaps: [Double]

    public init(gesture: TapGesture, taps: [TapFeatureVector], gaps: [Double]) {
        self.gesture = gesture
        self.taps = taps
        self.gaps = gaps
    }
}

/// A sound that the user recorded so that Sidetap rejects it, such as talking.
public struct RejectionExample: Equatable, Sendable {
    public var label: String
    public var feature: TapFeatureVector

    public init(label: String, feature: TapFeatureVector) {
        self.label = label
        self.feature = feature
    }
}

/// Why an attempt at a calibration gesture has to be repeated.
public enum CalibrationRetry: Error, Equatable, Sendable {
    case tapCount(heard: Int, expected: TapGesture)
    case quality(GuidedCaptureQualityIssue)

    public var guidance: String {
        switch self {
        case .tapCount(let heard, let expected) where heard < expected.rawValue:
            return "Heard \(heard) of \(expected.rawValue) taps. Tap a little more firmly, and keep an even pace."
        case .tapCount(let heard, let expected):
            return "Heard \(heard) taps, and this step needs \(expected.rawValue). Pause before the next try."
        case .quality(let issue):
            return issue.guidance
        }
    }
}

/// The taps heard so far in one attempt at a calibration gesture.
public struct CalibrationAttempt: Equatable, Sendable {
    public private(set) var taps: [TapFeatureVector] = []
    private var times: [Double] = []

    public init() {}

    public mutating func add(_ feature: TapFeatureVector, at time: Double) {
        taps.append(feature)
        times.append(time)
    }

    /// Judges the attempt once no further tap can follow. The attempt counts
    /// only when it has exactly the gesture's taps and every tap is clean.
    public func result(expecting gesture: TapGesture) -> Result<CalibratedGesture, CalibrationRetry> {
        guard taps.count == gesture.rawValue else {
            return .failure(.tapCount(heard: taps.count, expected: gesture))
        }
        if let issue = taps.lazy.compactMap({ GuidedCaptureQuality.issue(for: $0.quality) }).first {
            return .failure(.quality(issue))
        }
        return .success(CalibratedGesture(
            gesture: gesture,
            taps: taps,
            gaps: zip(times.dropFirst(), times).map { $0 - $1 }
        ))
    }
}

public struct CalibrationSession: Sendable {
    public let repetitions: Int
    public var strategy: SensingStrategy
    public var gestures: [CalibratedGesture]
    public var attempt: CalibrationAttempt
    public var negativeSamples: [RejectionExample]
    public var negativeLabel: String?
    public var isArmed: Bool
    public var isSettling: Bool

    public init(
        strategy: SensingStrategy = .passive,
        repetitions: Int = CalibrationGuidance.repetitionsPerGesture
    ) {
        self.strategy = strategy
        self.repetitions = repetitions
        self.gestures = []
        self.attempt = CalibrationAttempt()
        self.negativeSamples = []
        self.negativeLabel = nil
        self.isArmed = false
        self.isSettling = false
    }

    public var currentGesture: TapGesture? {
        CalibrationGuidance.gestures.first { count(for: $0) < repetitions }
    }

    public var gesturesComplete: Bool { currentGesture == nil }
    public var totalRequired: Int { repetitions * CalibrationGuidance.gestures.count }
    public var progress: Double { Double(gestures.count) / Double(totalRequired) }

    public func count(for gesture: TapGesture) -> Int {
        gestures.filter { $0.gesture == gesture }.count
    }

    public func negativeCount(for label: String) -> Int {
        negativeSamples.filter { $0.label == label }.count
    }

    /// The longest pause between taps that live gestures allow: a little over
    /// the slowest calibrated pace, and never under the default.
    public var maximumTapGap: Double {
        let slowest = gestures.flatMap(\.gaps).max() ?? 0
        return min(max(slowest * 1.3, TapGestureCounter.maximumGap), CalibrationGuidance.longestGap)
    }
}
