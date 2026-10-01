import Foundation

public struct TimingDiagnostics: Codable, Equatable, Sendable {
    public var expectedCallbackMilliseconds: Double
    public var meanCallbackMilliseconds: Double
    public var callbackJitterMilliseconds: Double
    public var estimatedInputLatencyMilliseconds: Double
    public var callbackCount: Int

    public init(
        expectedCallbackMilliseconds: Double = 0,
        meanCallbackMilliseconds: Double = 0,
        callbackJitterMilliseconds: Double = 0,
        estimatedInputLatencyMilliseconds: Double = 0,
        callbackCount: Int = 0
    ) {
        self.expectedCallbackMilliseconds = expectedCallbackMilliseconds
        self.meanCallbackMilliseconds = meanCallbackMilliseconds
        self.callbackJitterMilliseconds = callbackJitterMilliseconds
        self.estimatedInputLatencyMilliseconds = estimatedInputLatencyMilliseconds
        self.callbackCount = callbackCount
    }
}

public struct MicrophoneDiagnostics: Codable, Equatable, Sendable {
    public var deviceName: String
    public var audioRoute: AudioRouteInfo?
    public var sampleRate: Double
    public var channelCount: Int
    public var channelNames: [String]
    public var bufferFrameCount: Int
    public var timing: TimingDiagnostics
    public var latestSignalQuality: SignalQuality?
    public var latestFrequencyResponse: [SpectrumBand]
    public var microphonePermissionGranted: Bool
    public var capturedAt: Date

    public init(
        deviceName: String = "Default system input",
        audioRoute: AudioRouteInfo? = nil,
        sampleRate: Double = 0,
        channelCount: Int = 0,
        channelNames: [String] = [],
        bufferFrameCount: Int = 0,
        timing: TimingDiagnostics = TimingDiagnostics(),
        latestSignalQuality: SignalQuality? = nil,
        latestFrequencyResponse: [SpectrumBand] = [],
        microphonePermissionGranted: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.deviceName = deviceName
        self.audioRoute = audioRoute
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.channelNames = channelNames
        self.bufferFrameCount = bufferFrameCount
        self.timing = timing
        self.latestSignalQuality = latestSignalQuality
        self.latestFrequencyResponse = latestFrequencyResponse
        self.microphonePermissionGranted = microphonePermissionGranted
        self.capturedAt = capturedAt
    }
}

public struct CallbackTimingAccumulator: Sendable {
    private var intervals: [Double] = []
    private var lastTimestamp: Double?
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    public mutating func record(timestamp: Double) {
        if let lastTimestamp {
            intervals.append((timestamp - lastTimestamp) * 1_000)
            if intervals.count > capacity { intervals.removeFirst(intervals.count - capacity) }
        }
        lastTimestamp = timestamp
    }

    public func diagnostics(expectedMilliseconds: Double, inputLatencyMilliseconds: Double) -> TimingDiagnostics {
        guard !intervals.isEmpty else {
            return TimingDiagnostics(
                expectedCallbackMilliseconds: expectedMilliseconds,
                estimatedInputLatencyMilliseconds: inputLatencyMilliseconds
            )
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let jitter = sqrt(intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count))
        return TimingDiagnostics(
            expectedCallbackMilliseconds: expectedMilliseconds,
            meanCallbackMilliseconds: mean,
            callbackJitterMilliseconds: jitter,
            estimatedInputLatencyMilliseconds: inputLatencyMilliseconds,
            callbackCount: intervals.count
        )
    }
}

public struct DiagnosticCaptureRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var zone: DeskZone?
    public var feature: TapFeatureVector
    public var responseLatencyMilliseconds: Double

    public init(
        id: UUID = UUID(),
        label: String,
        zone: DeskZone?,
        feature: TapFeatureVector,
        responseLatencyMilliseconds: Double
    ) {
        self.id = id
        self.label = label
        self.zone = zone
        self.feature = feature
        self.responseLatencyMilliseconds = responseLatencyMilliseconds
    }
}

public struct DiagnosticSessionReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var microphone: MicrophoneDiagnostics
    public var captures: [DiagnosticCaptureRecord]
    public var approachComparison: ApproachComparison?
    public var recordingsRetained: Bool

    public init(
        generatedAt: Date = Date(),
        microphone: MicrophoneDiagnostics,
        captures: [DiagnosticCaptureRecord],
        approachComparison: ApproachComparison?,
        recordingsRetained: Bool
    ) {
        self.generatedAt = generatedAt
        self.microphone = microphone
        self.captures = captures
        self.approachComparison = approachComparison
        self.recordingsRetained = recordingsRetained
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
