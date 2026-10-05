import AppKit
import Combine
import Foundation
import SidetapCore

enum SidetapStorageError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let area):
            return "\(area) storage is unavailable. Sidetap did not save this change."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .live
    /// The saved calibration and actions, or nil before the first calibration.
    @Published private(set) var profile: SidetapProfile?
    @Published private(set) var lastDecision: ClassificationDecision?
    @Published private(set) var lastGesture: TapGesture?
    @Published private(set) var pendingTapCount = 0
    @Published private(set) var statusMessage = "Ready to learn your taps"
    @Published private(set) var calibrationSession: CalibrationSession?
    @Published private(set) var diagnosticCaptures: [DiagnosticCaptureRecord] = []
    @Published var diagnosticLabel = "Tap"
    @Published var diagnosticCaptureArmed = false
    /// What to change before the next calibration attempt, when the last one didn't count.
    @Published private(set) var calibrationGuidance: String?
    @Published var debugRecordingEnabled = false
    @Published private(set) var hasDebugRecordings = false
    @Published var errorMessage: String?

    let audio = AudioCaptureService()
    @Published var calibrationStrategy = SensingStrategy.passive

    private let profileStore: ProfileStore?
    private let debugStore: DebugRecordingStore?
    private let actionDispatcher = LocalActionDispatcher()
    private var gesture = TapGestureCounter()
    private var gestureTask: Task<Void, Never>?
    private var calibrationAcceptAfter = Date.distantPast
    private var calibrationArmTask: Task<Void, Never>?
    private var calibrationAttemptTask: Task<Void, Never>?
    private var pausedByUser = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        var startupErrors: [String] = []
        do { profileStore = try ProfileStore() }
        catch {
            profileStore = nil
            startupErrors.append("Calibration: \(error.localizedDescription)")
        }
        do { debugStore = try DebugRecordingStore() }
        catch {
            debugStore = nil
            startupErrors.append("Debug recordings: \(error.localizedDescription)")
        }

        if let debugStore {
            do { hasDebugRecordings = try debugStore.containsRecordings() }
            catch { startupErrors.append("Debug recordings: \(error.localizedDescription)") }
        }
        if let profileStore {
            do { profile = try profileStore.load() }
            catch { startupErrors.append("Calibration: \(error.localizedDescription)") }
        }
        if let profile {
            calibrationStrategy = profile.sensingStrategy
        }
        if !startupErrors.isEmpty {
            statusMessage = "Local storage needs attention"
            errorMessage = "Some local data could not be opened:\n\n" + startupErrors.joined(separator: "\n")
        }

        audio.onObservation = { [weak self] observation in
            self?.handle(observation)
        }
        audio.onRouteInvalidated = { [weak self] message in
            self?.disarmAllCaptureIntents()
            self?.statusMessage = "Built-in audio route required"
            self?.errorMessage = message
        }
        actionDispatcher.onAsyncError = { [weak self] error in
            self?.errorMessage = "The assigned action failed. \(error.localizedDescription)"
        }
        audio.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    var guidedSection: AppSection? {
        GuidedNavigationGate.guidedSection(calibrationActive: calibrationSession != nil)
    }

    func canNavigate(to candidate: AppSection) -> Bool {
        GuidedNavigationGate.canNavigate(to: candidate, guidedSection: guidedSection)
    }

    var targetStrategy: SensingStrategy {
        SensingStrategyResolver.resolve(
            calibration: calibrationSession?.strategy,
            profile: profile?.sensingStrategy
        )
    }

    func activate() async {
        do {
            try await audio.start(strategy: targetStrategy)
            if let gesture = calibrationSession?.currentGesture {
                statusMessage = "Calibration ready • \(gesture.displayName) • start listening when ready"
            } else {
                statusMessage = profile == nil ? "Listening • calibration needed" : "Listening for taps"
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Microphone unavailable"
        }
    }

    func activateOnLaunch() async {
        guard profile != nil else {
            section = .calibrate
            statusMessage = "Setup required • calibrate your taps"
            return
        }

        switch audio.authorizationState {
        case .authorized:
            await activate()
        case .notDetermined:
            statusMessage = profile == nil
                ? "Microphone access will be requested when calibration begins"
                : "Press Resume to enable microphone access"
        case .unavailable:
            statusMessage = "Microphone access is off"
        }
    }

    func togglePause() {
        if audio.isListening {
            pausedByUser = true
            disarmAllCaptureIntents()
            audio.stop()
            statusMessage = "Paused"
        } else if profile == nil && guidedSection == nil {
            openSetup()
        } else {
            pausedByUser = false
            Task { await activate() }
        }
    }

    func openSetup() {
        guard guidedSection == nil else { return }
        section = .calibrate
        statusMessage = "Setup required • calibrate your taps"
    }

    func beginCalibration() {
        pausedByUser = false
        calibrationArmTask?.cancel()
        calibrationAttemptTask?.cancel()
        let strategy = calibrationStrategy
        calibrationSession = CalibrationSession(strategy: strategy)
        calibrationGuidance = nil
        calibrationAcceptAfter = Date().addingTimeInterval(0.5)
        section = .calibrate
        statusMessage = "Calibration • \(TapGesture.double.displayName)"
        Task {
            do {
                try await prepareGuidedAudio(to: strategy)
                guard calibrationSession != nil,
                      audio.isListening,
                      audio.strategy == strategy else { return }
                armCalibration()
            }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func prepareRecalibration() {
        guard guidedSection == nil else { return }
        section = .calibrate
    }

    func cancelCalibration() {
        calibrationArmTask?.cancel()
        calibrationAttemptTask?.cancel()
        calibrationSession = nil
        calibrationGuidance = nil
        statusMessage = "Calibration cancelled"
        Task {
            do { try await reconfigureListeningAudio(to: targetStrategy) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func armCalibration() {
        guard var session = calibrationSession, let gesture = session.currentGesture else { return }
        calibrationArmTask?.cancel()
        session.isArmed = false
        session.isSettling = true
        calibrationGuidance = nil
        calibrationSession = session
        statusMessage = "Get ready • listening starts in one second"
        scheduleCalibrationArm(for: gesture, delayNanoseconds: 1_000_000_000)
    }

    private func scheduleCalibrationArm(for gesture: TapGesture, delayNanoseconds: UInt64) {
        calibrationArmTask?.cancel()
        calibrationArmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  var current = self.calibrationSession,
                  self.audio.isListening,
                  self.audio.strategy == current.strategy,
                  current.currentGesture == gesture,
                  current.isSettling else { return }
            current.isSettling = false
            current.isArmed = true
            current.attempt = CalibrationAttempt()
            self.calibrationAcceptAfter = Date()
            self.calibrationSession = current
            self.statusMessage = "Listening • \(gesture.displayName) \(current.count(for: gesture) + 1) of \(current.repetitions)"
        }
    }

    func collectNegativeExamples(label: String?) {
        calibrationSession?.negativeLabel = label
        calibrationSession?.isArmed = label != nil
        calibrationSession?.isSettling = false
        calibrationGuidance = nil
        calibrationAcceptAfter = Date().addingTimeInterval(label == nil ? 0 : 0.8)
        if let label {
            statusMessage = "Rejection training • make a \(label.lowercased()) sound"
        } else {
            statusMessage = "Calibration gestures complete"
        }
    }

    func clearNegativeExamples(label: String) {
        guard var session = calibrationSession else { return }
        session.negativeSamples.removeAll { $0.label == label }
        if session.negativeLabel == label {
            session.negativeLabel = nil
            session.isArmed = false
            session.isSettling = false
        }
        calibrationGuidance = nil
        calibrationSession = session
        statusMessage = "Cleared \(label.lowercased()) examples"
    }

    func undoLastCalibrationGesture() {
        calibrationArmTask?.cancel()
        calibrationAttemptTask?.cancel()
        guard var session = calibrationSession else { return }
        if session.negativeLabel != nil, !session.negativeSamples.isEmpty {
            session.negativeSamples.removeLast()
        } else if !session.gestures.isEmpty {
            session.gestures.removeLast()
        }
        session.attempt = CalibrationAttempt()
        session.isArmed = false
        session.isSettling = false
        calibrationGuidance = nil
        calibrationSession = session
        calibrationAcceptAfter = Date().addingTimeInterval(0.35)
        if let gesture = session.currentGesture {
            statusMessage = "\(gesture.displayName) \(session.count(for: gesture) + 1) of \(session.repetitions) • start listening when ready"
        }
    }

    func finishCalibration(openActions: Bool = false) {
        guard let session = calibrationSession, session.gesturesComplete else { return }
        do {
            let classifier = try TrainedTapClassifier.train(
                gestures: session.gestures.map(\.taps),
                negativeExamples: session.negativeSamples.map(\.feature)
            )
            // Recalibrating keeps the gestures and their actions.
            let calibrated = SidetapProfile(
                classifier: classifier,
                maximumTapGap: session.maximumTapGap,
                actions: profile?.actions ?? [:]
            )
            guard let profileStore else { throw SidetapStorageError.unavailable("Calibration") }
            try profileStore.save(calibrated)
            profile = calibrated
            calibrationArmTask?.cancel()
            calibrationSession = nil
            calibrationGuidance = nil
            section = openActions ? .actions : .live
            statusMessage = "Calibration saved • listening"
            Task {
                do { try await reconfigureListeningAudio(to: calibrated.sensingStrategy) }
                catch { errorMessage = error.localizedDescription }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func armDiagnosticCapture() {
        diagnosticCaptureArmed = true
        statusMessage = "Diagnostic armed • make a \(diagnosticLabel.lowercased()) sound"
    }

    func exportDiagnosticReport() {
        let report = DiagnosticSessionReport(
            microphone: audio.diagnostics,
            captures: diagnosticCaptures,
            recordingsRetained: debugRecordingEnabled
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sidetap-diagnostic-\(Self.fileTimestamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try report.jsonData().write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }

    func setDebugRecordingEnabled(_ enabled: Bool) {
        guard enabled else {
            debugRecordingEnabled = false
            return
        }
        guard debugStore != nil else {
            debugRecordingEnabled = false
            errorMessage = SidetapStorageError.unavailable("Debug recording").localizedDescription
            return
        }
        debugRecordingEnabled = true
    }

    func clearDebugRecordings() {
        do {
            guard let debugStore else { throw SidetapStorageError.unavailable("Debug recording") }
            try debugStore.clear()
            hasDebugRecordings = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updateAction(for gesture: TapGesture, action: ActionConfiguration) -> Bool {
        updateProfile { $0.setAction(action, for: gesture) }
    }

    func addGesture() {
        updateProfile { $0.addGesture() }
    }

    func removeLastGesture() {
        updateProfile { $0.removeLastGesture() }
    }

    @discardableResult
    private func updateProfile(_ change: (inout SidetapProfile) -> Void) -> Bool {
        guard var updatedProfile = profile else { return false }
        change(&updatedProfile)
        do {
            guard let profileStore else { throw SidetapStorageError.unavailable("Calibration") }
            try profileStore.save(updatedProfile)
            profile = updatedProfile
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func testAction(_ action: ActionConfiguration) {
        do { try actionDispatcher.perform(action) }
        catch { errorMessage = error.localizedDescription }
    }

    private func handle(_ observation: TapObservation) {
        if debugRecordingEnabled {
            let label = currentCaptureLabel
            do {
                guard let debugStore else { throw SidetapStorageError.unavailable("Debug recording") }
                try debugStore.save(
                   observation,
                   label: label,
                   sampleRate: audio.diagnostics.sampleRate
                )
                hasDebugRecordings = true
            } catch {
                debugRecordingEnabled = false
                errorMessage = "Debug recording stopped because the WAV could not be saved. \(error.localizedDescription)"
            }
        }

        if var calibration = calibrationSession {
            handleCalibration(observation, session: &calibration)
            calibrationSession = calibration
            return
        }

        if section == .diagnostics {
            if diagnosticCaptureArmed {
                let capture = DiagnosticCaptureRecord(
                    label: diagnosticLabel,
                    feature: observation.feature,
                    responseLatencyMilliseconds: responseLatencyMilliseconds(for: observation)
                )
                diagnosticCaptures.append(capture)
                diagnosticCaptureArmed = false
                statusMessage = "Diagnostic captured • \(observation.feature.quality.summary)"
            }
            return
        }

        guard let profile else {
            statusMessage = "Tap detected • calibration needed"
            return
        }
        if observation.feature.quality.noiseFloorRMS > SignalQuality.maximumRoomNoiseFloorRMS {
            statusMessage = "Room too noisy • actions paused"
            return
        }
        if followsTypingOrClick(observation) {
            statusMessage = "Tap ignored • typing or clicking"
            return
        }
        var decision = profile.classifier.predict(observation.feature)
        decision.processingLatencyMilliseconds = observation.processingLatencyMilliseconds
        lastDecision = decision
        guard decision.isTap else {
            statusMessage = "Rejected • \(decision.rejectionReason?.displayName ?? "low confidence")"
            return
        }
        let count = gesture.add(at: observation.eventHostTimeSeconds, maximumGap: profile.maximumTapGap)
        gestureTask?.cancel()
        // Only the gesture with the most taps can run at once. Any other has to
        // wait in case one more tap follows.
        guard count < (profile.gestures.last?.rawValue ?? 0) else {
            completeGesture()
            return
        }
        pendingTapCount = count
        statusMessage = TapGesture(rawValue: count).map { "\($0.displayName) • waiting in case of another tap" }
            ?? "Tap heard • tap again"
        // The next tap can start up to the profile's gap after this one, and a tap
        // takes about 0.25 s to be detected (measured: 213 ms at the 90th percentile).
        let deadline = observation.eventHostTimeSeconds + profile.maximumTapGap + 0.25
        gestureTask = Task { [weak self] in
            let wait = deadline - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.completeGesture()
        }
    }

    private func completeGesture() {
        gestureTask?.cancel()
        pendingTapCount = 0
        guard let profile, let completed = TapGesture(rawValue: gesture.finish()) else {
            statusMessage = "Single tap ignored"
            return
        }
        lastGesture = completed
        guard section == .live else {
            statusMessage = "\(completed.displayName) • actions paused outside Desk"
            return
        }
        statusMessage = completed.displayName
        do { try actionDispatcher.perform(profile.action(for: completed)) }
        catch {
            statusMessage = "\(completed.displayName) • action failed"
            errorMessage = error.localizedDescription
        }
    }

    private func handleCalibration(_ observation: TapObservation, session: inout CalibrationSession) {
        guard session.isArmed else { return }
        guard Date() >= calibrationAcceptAfter else { return }
        guard observation.feature.strategy == session.strategy else { return }

        if session.currentGesture != nil {
            // Collect every tap of the attempt, and judge it once no further tap can follow.
            session.attempt.add(observation.feature, at: observation.eventHostTimeSeconds)
            calibrationGuidance = nil
            let deadline = observation.eventHostTimeSeconds + CalibrationGuidance.longestGap + 0.25
            calibrationAttemptTask?.cancel()
            calibrationAttemptTask = Task { [weak self] in
                let wait = deadline - ProcessInfo.processInfo.systemUptime
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                self?.completeCalibrationAttempt()
            }
        } else if let label = session.negativeLabel {
            // Rejection examples are intentionally not required to resemble a
            // clean tap. Their job is to represent talking, typing, laptop
            // touches, and other sounds that should never run an action.
            calibrationGuidance = nil
            session.negativeSamples.append(RejectionExample(label: label, feature: observation.feature))
            statusMessage = "\(label) examples • \(session.negativeCount(for: label)) captured"
        }
    }

    private func completeCalibrationAttempt() {
        guard var session = calibrationSession, session.isArmed, let gesture = session.currentGesture else { return }
        let result = session.attempt.result(expecting: gesture)
        session.attempt = CalibrationAttempt()
        switch result {
        case .failure(let retry):
            calibrationGuidance = retry.guidance
            statusMessage = "Not counted • try that \(gesture.displayName.lowercased()) again"
        case .success(let calibrated):
            calibrationGuidance = nil
            session.gestures.append(calibrated)
            if let next = session.currentGesture, next != gesture {
                session.isArmed = false
                session.isSettling = true
                statusMessage = "\(gesture.displayName)s saved • \(next.displayName.lowercased())s are next"
                scheduleCalibrationArm(for: next, delayNanoseconds: 2_000_000_000)
            } else if session.currentGesture != nil {
                statusMessage = "Listening • \(gesture.displayName) \(session.count(for: gesture) + 1) of \(session.repetitions)"
            } else {
                session.isArmed = false
                session.isSettling = false
                statusMessage = "Calibration captured • save, or add sounds to reject"
            }
        }
        calibrationSession = session
    }

    private var currentCaptureLabel: String {
        if let session = calibrationSession {
            if let gesture = session.currentGesture { return "calibration-\(gesture.rawValue)-taps" }
            if let label = session.negativeLabel { return "negative-\(label)" }
        }
        return diagnosticLabel
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// A keystroke or trackpad click shakes the MacBook like a tap, and no
    /// frequency filter tells them apart, so taps near one are ignored. Only
    /// the live path checks this; calibration still records typing as a
    /// negative example. Only physical input counts, so the ⌘V that the Paste
    /// text action sends doesn't look like typing.
    private func followsTypingOrClick(_ observation: TapObservation) -> Bool {
        let inputs: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp
        ]
        let secondsSinceInput = inputs
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? .infinity
        let lastInputHostTime = ProcessInfo.processInfo.systemUptime - secondsSinceInput
        // Also covers input after the tap: the 90 ms analysis window means the
        // check runs a little after the sound.
        return lastInputHostTime >= observation.eventHostTimeSeconds - 0.3
    }

    private func responseLatencyMilliseconds(for observation: TapObservation) -> Double {
        AudioTimeline.elapsedMilliseconds(
            since: observation.eventHostTimeSeconds,
            now: ProcessInfo.processInfo.systemUptime
        )
    }

    private func disarmAllCaptureIntents() {
        calibrationArmTask?.cancel()
        calibrationAttemptTask?.cancel()
        calibrationSession?.attempt = CalibrationAttempt()
        calibrationSession?.isArmed = false
        calibrationSession?.isSettling = false
        calibrationSession?.negativeLabel = nil
        diagnosticCaptureArmed = false
        calibrationGuidance = nil
    }

    private func reconfigureListeningAudio(to strategy: SensingStrategy) async throws {
        guard audio.isListening else { return }
        try await audio.reconfigure(strategy: strategy)
    }

    private func prepareGuidedAudio(to strategy: SensingStrategy) async throws {
        guard !pausedByUser else { return }
        if audio.isListening {
            try await audio.reconfigure(strategy: strategy)
        } else {
            try await audio.start(strategy: strategy)
        }
    }
}
