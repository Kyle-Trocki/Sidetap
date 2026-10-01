import CoreLocation
import Foundation

public enum ZoneActionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case sound
    case copyText
    case pasteText
    case speakText
    case openURL
    case runShortcut
    case openApplication
    case openItem
    case runShellCommand
    case screenshotClipboard
    case screenshotSelection

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "Visual only"
        case .sound: return "Play sound"
        case .copyText: return "Copy text"
        case .pasteText: return "Paste text"
        case .speakText: return "Speak text"
        case .openURL: return "Open website"
        case .runShortcut: return "Run Shortcut"
        case .openApplication: return "Open or focus app"
        case .openItem: return "Open file or folder"
        case .runShellCommand: return "Run shell command"
        // The case names are saved in profiles and predate the destination option.
        case .screenshotClipboard: return "Screenshot"
        case .screenshotSelection: return "Screenshot selected area"
        }
    }
}

/// The gestures that run actions: a double or a triple tap anywhere on the desk.
public enum TapGesture: Int, CaseIterable, Codable, Sendable, Identifiable {
    case double = 2
    case triple = 3

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .double: return "Double tap"
        case .triple: return "Triple tap"
        }
    }
}

/// Where a screenshot action puts its image. A screenshot action stores the raw
/// value in its `text`; anything unrecognized, including empty, means the Desktop.
public enum ScreenshotDestination: String, CaseIterable, Sendable, Identifiable {
    case desktop
    case clipboard
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .desktop: return "Save to Desktop"
        case .clipboard: return "Copy to clipboard"
        case .both: return "Desktop and clipboard"
        }
    }
}

public struct ZoneActionConfiguration: Codable, Equatable, Sendable {
    public var kind: ZoneActionKind
    public var soundName: String
    public var text: String
    public var bookmarkData: Data?

    public init(
        kind: ZoneActionKind = .none,
        soundName: String = "Tink",
        text: String = "",
        bookmarkData: Data? = nil
    ) {
        self.kind = kind
        self.soundName = soundName
        self.text = text
        self.bookmarkData = bookmarkData
    }
}

public struct ZoneConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var zone: DeskZone
    public var action: ZoneActionConfiguration
    public var id: Int { zone.rawValue }

    public init(zone: DeskZone, action: ZoneActionConfiguration = ZoneActionConfiguration()) {
        self.zone = zone
        self.action = action
    }
}

public struct CalibrationSummary: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var samplesPerZone: [Int]
    public var leaveOneOutAccuracy: Double?
    public var capturedAt: Date

    public init(sampleCount: Int, samplesPerZone: [Int], leaveOneOutAccuracy: Double?, capturedAt: Date = Date()) {
        self.sampleCount = sampleCount
        self.samplesPerZone = samplesPerZone
        self.leaveOneOutAccuracy = leaveOneOutAccuracy
        self.capturedAt = capturedAt
    }
}

public struct ProfileLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

public struct SidetapProfile: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 3
    /// How close, in meters, the Mac must be to a pinned desk to switch to it.
    public static let locationRadius: CLLocationDistance = 300

    public var version: Int
    public var id: UUID
    public var name: String
    public var surfaceDescription: String
    public var laptopPositionNote: String
    public var createdAt: Date
    public var updatedAt: Date
    public var classifier: TrainedTapClassifier
    public var calibration: CalibrationSummary
    public var zones: [ZoneConfiguration]
    /// Where this desk is. Sidetap switches to the nearest pinned profile when
    /// the Mac arrives there. Profiles saved before this field decode as nil.
    public var location: ProfileLocation?
    /// What a double tap and a triple tap run. Profiles saved before gestures
    /// decode as nil, which means no action.
    public var doubleTapAction: ZoneActionConfiguration?
    public var tripleTapAction: ZoneActionConfiguration?

    public init(
        id: UUID = UUID(),
        name: String,
        surfaceDescription: String,
        laptopPositionNote: String,
        classifier: TrainedTapClassifier,
        calibration: CalibrationSummary,
        zones: [ZoneConfiguration] = DeskZone.allCases.map { ZoneConfiguration(zone: $0) }
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.name = name
        self.surfaceDescription = surfaceDescription
        self.laptopPositionNote = laptopPositionNote
        self.createdAt = Date()
        self.updatedAt = Date()
        self.classifier = classifier
        self.calibration = calibration
        self.zones = zones
    }

    public var sensingStrategy: SensingStrategy { classifier.strategy }

    public func action(for zone: DeskZone) -> ZoneActionConfiguration {
        zones.first(where: { $0.zone == zone })?.action ?? ZoneActionConfiguration(kind: .none)
    }

    public func action(for gesture: TapGesture) -> ZoneActionConfiguration {
        (gesture == .double ? doubleTapAction : tripleTapAction) ?? ZoneActionConfiguration(kind: .none)
    }

    public mutating func setAction(_ action: ZoneActionConfiguration, for gesture: TapGesture) {
        switch gesture {
        case .double: doubleTapAction = action
        case .triple: tripleTapAction = action
        }
    }
}

extension Array where Element == SidetapProfile {
    /// The pinned profile closest to `location`, or nil when none is within `radius` meters.
    // ponytail: location alone can't tell apart two desks in one building; match Wi-Fi or displays too if that's needed.
    public func nearest(to location: CLLocation, within radius: CLLocationDistance = SidetapProfile.locationRadius) -> SidetapProfile? {
        let distances = compactMap { profile in
            profile.location.map { pin in
                (profile, location.distance(from: CLLocation(latitude: pin.latitude, longitude: pin.longitude)))
            }
        }
        return distances.filter { $0.1 <= radius }.min { $0.1 < $1.1 }?.0
    }
}

public enum ProfileStoreError: Error, LocalizedError, Equatable {
    case invalidCurrentTopology(String)
    case invalidCurrentClassifier(String)
    case invalidCurrentCalibration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentTopology(let filename):
            return "The current profile \(filename) does not contain exactly the four supported zones."
        case .invalidCurrentClassifier(let filename):
            return "The classifier in \(filename) is incomplete or internally inconsistent. Recalibrate this desk."
        case .invalidCurrentCalibration(let filename):
            return "The calibration summary in \(filename) does not match its four-zone classifier. Recalibrate this desk."
        }
    }
}

public final class ProfileStore {
    private struct VersionEnvelope: Decodable {
        var version: Int
    }

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = support.appendingPathComponent("Sidetap/Profiles", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func loadAll() throws -> [SidetapProfile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        let requiredZones = Set(DeskZone.allCases)
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(VersionEnvelope.self, from: data)
            guard envelope.version == SidetapProfile.currentVersion else { return nil }
            let profile = try decoder().decode(SidetapProfile.self, from: data)
            guard profile.zones.count == requiredZones.count,
                  Set(profile.zones.map(\.zone)) == requiredZones else {
                throw ProfileStoreError.invalidCurrentTopology(url.lastPathComponent)
            }
            guard classifierIsValid(profile.classifier, requiredZones: requiredZones) else {
                throw ProfileStoreError.invalidCurrentClassifier(url.lastPathComponent)
            }
            guard calibrationIsValid(profile.calibration, classifier: profile.classifier) else {
                throw ProfileStoreError.invalidCurrentCalibration(url.lastPathComponent)
            }
            return profile
        }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ profile: SidetapProfile) throws {
        var updated = profile
        updated.updatedAt = Date()
        let data = try encoder().encode(updated)
        try data.write(to: url(for: updated.id), options: .atomic)
    }

    public func delete(_ profile: SidetapProfile) throws {
        let url = url(for: profile.id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func classifierIsValid(
        _ classifier: TrainedTapClassifier,
        requiredZones: Set<DeskZone>
    ) -> Bool {
        let dimension = classifier.featureNames.count
        guard dimension > 0,
              classifier.center.count == dimension,
              classifier.scales.count == dimension,
              classifier.featureWeights.count == dimension,
              classifier.center.allSatisfy(\.isFinite),
              classifier.scales.allSatisfy({ $0.isFinite && $0 > 0 }),
              classifier.featureWeights.allSatisfy({ $0.isFinite && $0 > 0 }),
              classifier.outlierThreshold.isFinite,
              classifier.outlierThreshold > 0,
              classifier.minimumConfidence.isFinite,
              (0...1).contains(classifier.minimumConfidence) else {
            return false
        }
        if let noveltyThreshold = classifier.positiveNoveltyThreshold,
           !noveltyThreshold.isFinite || noveltyThreshold <= 0 {
            return false
        }
        if let linearModel = classifier.linearZoneModel {
            guard linearModel.coefficients.count == DeskZone.allCases.count,
                  linearModel.coefficients.allSatisfy({ row in
                      row.count == dimension + 1 && row.allSatisfy(\.isFinite)
                  }) else {
                return false
            }
        }

        let positives = classifier.positiveExamples
        guard positives.allSatisfy({ $0.zone != nil }),
              classifier.negativeExamples.allSatisfy({ $0.zone == nil }),
              Set(positives.compactMap(\.zone)) == requiredZones,
              requiredZones.allSatisfy({ zone in
                  positives.filter { $0.zone == zone }.count >= 2
              }) else {
            return false
        }

        return (positives + classifier.negativeExamples).allSatisfy { example in
            let feature = example.feature
            return feature.strategy == classifier.strategy
                && feature.names == classifier.featureNames
                && feature.values.count == dimension
                && feature.values.allSatisfy(\.isFinite)
                && signalQualityIsValid(feature.quality)
        }
    }

    private func calibrationIsValid(
        _ calibration: CalibrationSummary,
        classifier: TrainedTapClassifier
    ) -> Bool {
        let actualCounts = DeskZone.allCases.map { zone in
            classifier.positiveExamples.filter { $0.zone == zone }.count
        }
        guard calibration.sampleCount == classifier.positiveExamples.count,
              calibration.samplesPerZone == actualCounts else {
            return false
        }
        guard let agreement = calibration.leaveOneOutAccuracy else { return true }
        return agreement.isFinite && (0...1).contains(agreement)
    }

    private func signalQualityIsValid(_ quality: SignalQuality) -> Bool {
        quality.signalToNoiseDB.isFinite
            && quality.peakAmplitude.isFinite && quality.peakAmplitude >= 0
            && quality.rmsAmplitude.isFinite && quality.rmsAmplitude >= 0
            && quality.clippingFraction.isFinite && (0...1).contains(quality.clippingFraction)
            && quality.noiseFloorRMS.isFinite && quality.noiseFloorRMS >= 0
            && quality.durationMilliseconds.isFinite && quality.durationMilliseconds >= 0
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public final class EvaluationStore {
    private struct TopologyEnvelope: Decodable {
        var topologyZoneCount: Int?
    }

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = support.appendingPathComponent("Sidetap/Evaluations", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func save(_ report: EvaluationReport) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "evaluation-\(formatter.string(from: report.completedAt)).json"
        let url = directory.appendingPathComponent(filename)
        try report.jsonData().write(to: url, options: .atomic)
        let csvURL = url.deletingPathExtension().appendingPathExtension("csv")
        try Data(report.csv().utf8).write(to: csvURL, options: .atomic)
        return url
    }

    public func loadAll() throws -> [EvaluationReport] {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            let envelope = try decoder.decode(TopologyEnvelope.self, from: data)
            guard envelope.topologyZoneCount == DeskZone.allCases.count else { return nil }
            return try decoder.decode(EvaluationReport.self, from: data)
        }
            .sorted { $0.completedAt > $1.completedAt }
    }
}

public final class ApproachComparisonStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("Sidetap", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("approach-comparison.json")
        }
    }

    public func save(_ comparison: ApproachComparison) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(comparison).write(to: fileURL, options: .atomic)
    }

    public func load() throws -> ApproachComparison? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let comparison = try decoder.decode(ApproachComparison.self, from: Data(contentsOf: fileURL))
        guard comparison.topologyZoneCount == DeskZone.allCases.count else { return nil }
        return comparison
    }
}
