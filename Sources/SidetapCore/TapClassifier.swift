import Foundation

public struct ClassificationDecision: Codable, Equatable, Sendable {
    /// How closely the sound matches the calibrated taps, from 0 to 1.
    public var confidence: Double
    public var signalStrength: Double
    public var rejectionReason: RejectionReason?
    public var processingLatencyMilliseconds: Double

    public init(
        confidence: Double,
        signalStrength: Double,
        rejectionReason: RejectionReason?,
        processingLatencyMilliseconds: Double = 0
    ) {
        self.confidence = confidence
        self.signalStrength = signalStrength
        self.rejectionReason = rejectionReason
        self.processingLatencyMilliseconds = processingLatencyMilliseconds
    }

    /// Whether the sound is one of the calibrated taps.
    public var isTap: Bool { rejectionReason == nil }
}

public enum ClassifierTrainingError: Error, LocalizedError, Equatable {
    case notEnoughSamples
    case inconsistentFeatures

    public var errorDescription: String? {
        switch self {
        case .notEnoughSamples: return "At least two calibrated gestures are required."
        case .inconsistentFeatures: return "All calibration examples must use the same sensing strategy and feature schema."
        }
    }
}

/// Decides whether a sound is one of the calibrated taps. It learns what a tap
/// sounds like, not where it lands: a sound passes when it is close enough to a
/// calibrated tap and no closer to a sound that the user asked to reject.
public struct TrainedTapClassifier: Codable, Equatable, Sendable {
    public var strategy: SensingStrategy
    public var featureNames: [String]
    public var center: [Double]
    public var scales: [Double]
    public var positiveExamples: [TapFeatureVector]
    public var negativeExamples: [TapFeatureVector]
    public var noveltyThreshold: Double

    /// Trains on the taps of each calibrated gesture.
    public static func train(
        gestures: [[TapFeatureVector]],
        negativeExamples: [TapFeatureVector] = []
    ) throws -> TrainedTapClassifier {
        let positives = gestures.flatMap { $0 }
        guard gestures.filter({ !$0.isEmpty }).count >= 2, let first = positives.first else {
            throw ClassifierTrainingError.notEnoughSamples
        }
        let names = first.names
        let strategy = first.strategy
        guard !names.isEmpty,
              (positives + negativeExamples).allSatisfy({
                  $0.names == names && $0.values.count == names.count && $0.strategy == strategy
              }) else {
            throw ClassifierTrainingError.inconsistentFeatures
        }

        let dimensions = names.count
        var center = Array(repeating: 0.0, count: dimensions)
        var scales = Array(repeating: 1.0, count: dimensions)
        for dimension in 0..<dimensions {
            let values = positives.map { $0.values[dimension] }
            center[dimension] = median(values)
            let deviations = values.map { abs($0 - center[dimension]) }
            let robustScale = median(deviations) * 1.4826
            let mean = values.reduce(0, +) / Double(values.count)
            let standardDeviation = sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(values.count - 1, 1)))
            scales[dimension] = max(robustScale, standardDeviation * 0.35, 1e-6)
        }

        // A tap's nearest neighbor is usually the next tap of its own gesture,
        // which says little about how much taps vary from one gesture to the
        // next. Measure each tap against the other gestures instead.
        let normalized = gestures.map { $0.map { normalize($0.values, center: center, scales: scales) } }
        var nearestDistances: [Double] = []
        for (index, taps) in normalized.enumerated() {
            let others = normalized.enumerated().filter { $0.offset != index }.flatMap(\.element)
            for tap in taps {
                if let nearest = others.map({ distance(tap, $0) }).min() { nearestDistances.append(nearest) }
            }
        }

        return TrainedTapClassifier(
            strategy: strategy,
            featureNames: names,
            center: center,
            scales: scales,
            positiveExamples: positives,
            negativeExamples: negativeExamples,
            noveltyThreshold: max(quantile(nearestDistances, probability: 0.95) * 2.6, 0.95)
        )
    }

    public func predict(_ feature: TapFeatureVector) -> ClassificationDecision {
        guard feature.strategy == strategy,
              feature.names == featureNames,
              feature.values.count == center.count else {
            return rejected(feature, reason: .schemaMismatch)
        }
        if feature.quality.clippingFraction > SignalQuality.maximumReliableClippingFraction {
            return rejected(feature, reason: .clippedSignal)
        }
        if feature.quality.peakAmplitude < SignalQuality.minimumReliablePeakAmplitude {
            return rejected(feature, reason: .weakSignal)
        }
        if feature.quality.signalToNoiseDB < SignalQuality.minimumClassificationSignalToNoiseDB {
            return rejected(feature, reason: .lowSignalToNoise)
        }

        let input = Self.normalize(feature.values, center: center, scales: scales)
        let nearest: ([TapFeatureVector]) -> Double = { examples in
            examples.map {
                Self.distance(input, Self.normalize($0.values, center: center, scales: scales))
            }.min() ?? .infinity
        }
        let nearestPositive = nearest(positiveExamples)
        if nearestPositive > noveltyThreshold {
            return rejected(feature, reason: .outOfDistribution)
        }
        if nearest(negativeExamples) <= nearestPositive * 1.10 {
            return rejected(feature, reason: .resemblesNegativeExample)
        }

        return ClassificationDecision(
            confidence: min(max(1 - nearestPositive / noveltyThreshold, 0), 1),
            signalStrength: feature.quality.score,
            rejectionReason: nil
        )
    }

    private func rejected(_ feature: TapFeatureVector, reason: RejectionReason) -> ClassificationDecision {
        ClassificationDecision(confidence: 0, signalStrength: feature.quality.score, rejectionReason: reason)
    }

    private static func normalize(_ values: [Double], center: [Double], scales: [Double]) -> [Double] {
        zip(values, zip(center, scales)).map { value, pair in
            (value - pair.0) / max(pair.1, 1e-9)
        }
    }

    private static func distance(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let squared = zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + pow(pair.0 - pair.1, 2)
        }
        return sqrt(squared / Double(max(min(lhs.count, rhs.count), 1)))
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    private static func quantile(_ values: [Double], probability: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(max(probability, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }
}
