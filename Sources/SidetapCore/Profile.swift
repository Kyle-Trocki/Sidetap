import Foundation

public enum ActionKind: String, CaseIterable, Codable, Sendable, Identifiable {
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
    case pressKeys
    case mediaKey

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
        case .pressKeys: return "Press keyboard shortcut"
        case .mediaKey: return "Media control"
        }
    }
}

/// A gesture that runs an action: two or more taps anywhere on the desk. The
/// raw value is the number of taps.
public struct TapGesture: RawRepresentable, Hashable, Sendable, Identifiable {
    public static let double = TapGesture(taps: 2)
    public static let triple = TapGesture(taps: 3)

    public let rawValue: Int
    public var id: Int { rawValue }

    /// Nil below two taps: a single tap is never a gesture, because any stray
    /// knock on the desk would run its action.
    public init?(rawValue: Int) {
        guard rawValue >= 2 else { return nil }
        self.rawValue = rawValue
    }

    private init(taps: Int) { rawValue = taps }

    public var displayName: String {
        switch rawValue {
        case 2: return "Double tap"
        case 3: return "Triple tap"
        default: return "\(rawValue) taps"
        }
    }
}

/// The key a media control action presses. The action stores the raw value in
/// its `text`; anything unrecognized, including empty, means play or pause.
public enum MediaKey: String, CaseIterable, Sendable, Identifiable {
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .playPause: return "Play or pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
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

public struct ActionConfiguration: Codable, Equatable, Sendable {
    public var kind: ActionKind
    public var soundName: String
    public var text: String
    public var bookmarkData: Data?
    /// The key and modifiers that a keyboard shortcut action presses: a virtual
    /// key code and `CGEventFlags` bits. The action's `text` holds the label.
    public var keyCode: UInt16?
    public var keyModifiers: UInt64?

    public init(
        kind: ActionKind = .none,
        soundName: String = "Tink",
        text: String = "",
        bookmarkData: Data? = nil,
        keyCode: UInt16? = nil,
        keyModifiers: UInt64? = nil
    ) {
        self.kind = kind
        self.soundName = soundName
        self.text = text
        self.bookmarkData = bookmarkData
        self.keyCode = keyCode
        self.keyModifiers = keyModifiers
    }
}

/// Everything Sidetap saves: the calibration and what each gesture runs.
public struct SidetapProfile: Codable, Equatable, Sendable {
    /// Version 4 replaced the four-zone calibration with double-tap and
    /// triple-tap calibration, and replaced the per-desk profiles with this
    /// single one. Earlier files are skipped and need recalibrating.
    public static let currentVersion = 4

    public var version: Int
    public var classifier: TrainedTapClassifier
    /// The longest pause, in seconds, between two taps of one gesture. Learned
    /// from the pace of the calibrated double and triple taps, and used for
    /// every gesture, including the ones added later.
    public var maximumTapGap: Double
    /// What each gesture runs, keyed by tap count.
    public var actions: [Int: ActionConfiguration]

    public init(
        classifier: TrainedTapClassifier,
        maximumTapGap: Double = TapGestureCounter.maximumGap,
        actions: [Int: ActionConfiguration] = [:]
    ) {
        self.version = Self.currentVersion
        self.classifier = classifier
        self.maximumTapGap = maximumTapGap
        self.actions = actions
    }

    public var sensingStrategy: SensingStrategy { classifier.strategy }

    /// Every gesture, from a double tap up to the highest tap count that was
    /// added. A double and a triple tap are always there.
    public var gestures: [TapGesture] {
        (2...max(3, actions.keys.max() ?? 3)).compactMap(TapGesture.init(rawValue:))
    }

    public func action(for gesture: TapGesture) -> ActionConfiguration {
        actions[gesture.rawValue] ?? ActionConfiguration(kind: .none)
    }

    public mutating func setAction(_ action: ActionConfiguration, for gesture: TapGesture) {
        actions[gesture.rawValue] = action
    }

    /// Adds a gesture with one more tap than the highest so far.
    public mutating func addGesture() {
        guard let last = gestures.last, let next = TapGesture(rawValue: last.rawValue + 1) else { return }
        setAction(ActionConfiguration(), for: next)
    }

    /// Removes the gesture with the most taps. Double and triple taps stay.
    public mutating func removeLastGesture() {
        guard let last = gestures.last, last.rawValue > TapGesture.triple.rawValue else { return }
        actions[last.rawValue] = nil
    }
}

public enum ProfileStoreError: Error, LocalizedError, Equatable {
    case invalidCalibration

    public var errorDescription: String? {
        "The saved calibration is incomplete or internally inconsistent. Calibrate again."
    }
}

/// Keeps the one saved profile in a JSON file.
public final class ProfileStore {
    private struct VersionEnvelope: Decodable {
        var version: Int
    }

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
            self.fileURL = directory.appendingPathComponent("profile.json")
        }
    }

    /// The saved profile, or nil when nothing is saved or the file is from an
    /// earlier version.
    public func load() throws -> SidetapProfile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard try decoder.decode(VersionEnvelope.self, from: data).version == SidetapProfile.currentVersion else {
            return nil
        }
        let profile = try decoder.decode(SidetapProfile.self, from: data)
        guard classifierIsValid(profile.classifier),
              profile.maximumTapGap.isFinite, profile.maximumTapGap > 0 else {
            throw ProfileStoreError.invalidCalibration
        }
        return profile
    }

    public func save(_ profile: SidetapProfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profile).write(to: fileURL, options: .atomic)
    }

    private func classifierIsValid(_ classifier: TrainedTapClassifier) -> Bool {
        let dimension = classifier.featureNames.count
        guard dimension > 0,
              classifier.center.count == dimension,
              classifier.scales.count == dimension,
              classifier.center.allSatisfy(\.isFinite),
              classifier.scales.allSatisfy({ $0.isFinite && $0 > 0 }),
              classifier.noveltyThreshold.isFinite,
              classifier.noveltyThreshold > 0,
              classifier.positiveExamples.count >= 2 else {
            return false
        }

        return (classifier.positiveExamples + classifier.negativeExamples).allSatisfy { feature in
            feature.strategy == classifier.strategy
                && feature.names == classifier.featureNames
                && feature.values.count == dimension
                && feature.values.allSatisfy(\.isFinite)
                && signalQualityIsValid(feature.quality)
        }
    }

    private func signalQualityIsValid(_ quality: SignalQuality) -> Bool {
        quality.signalToNoiseDB.isFinite
            && quality.peakAmplitude.isFinite && quality.peakAmplitude >= 0
            && quality.rmsAmplitude.isFinite && quality.rmsAmplitude >= 0
            && quality.clippingFraction.isFinite && (0...1).contains(quality.clippingFraction)
            && quality.noiseFloorRMS.isFinite && quality.noiseFloorRMS >= 0
            && quality.durationMilliseconds.isFinite && quality.durationMilliseconds >= 0
    }
}
