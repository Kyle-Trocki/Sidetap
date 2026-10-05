import SidetapCore
import SwiftUI

struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @State private var showRejectionTraining = true

    var body: some View {
        Group {
            if let session = model.calibrationSession {
                activeCalibration(session)
            } else {
                setup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidetapTheme.background)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calibrate your taps")
                    .font(.title.weight(.semibold))
                Text("You double-tap \(CalibrationGuidance.repetitionsPerGesture) times, and then triple-tap \(CalibrationGuidance.repetitionsPerGesture) times. Sidetap learns how your taps sound and how fast you tap, and uses both for every gesture, including the ones you add later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Sensing") {
                    Picker("Approach", selection: $model.calibrationStrategy) {
                        ForEach(SensingStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    Text(model.calibrationStrategy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.calibrationStrategy != .passive {
                        Label("Uses a quiet repeating speaker chirp", systemImage: "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Before calibration") {
                    Label("Put the MacBook where it normally stays", systemImage: "macbook")
                    Label("Clear objects and cables that touch the MacBook", systemImage: "rectangle.dashed")
                    Label("Tap where and how you will in everyday use, and pause for a second between gestures", systemImage: "hand.tap")
                }

                Section {
                    Button(model.profile == nil ? "Begin Calibration" : "Recalibrate") {
                        model.beginCalibration()
                    }
                    .sidetapPrimaryButton()
                    .controlSize(.large)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeCalibration(_ session: CalibrationSession) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.currentGesture.map { "\($0.displayName)s" } ?? "Calibration captured")
                            .font(.title.weight(.semibold))
                        Text(session.gesturesComplete ? "Save the calibration, then assign actions." : instruction(for: session))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(session.gestures.count) of \(session.totalRequired)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: session.progress)
                    .accessibilityLabel("Calibration progress")

                if let gesture = session.currentGesture {
                    gestureControls(session, gesture: gesture)
                } else {
                    completionControls(session)
                }
            }
            .frame(maxWidth: 820)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // SwiftUI has its own TapGesture, so the one that counts taps needs its module name.
    private func gestureControls(_ session: CalibrationSession, gesture: SidetapCore.TapGesture) -> some View {
        VStack(spacing: 14) {
            if session.isSettling {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(session.gestures.isEmpty ? "Preparing…" : "Get ready • listening starts automatically")
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)
            } else if session.isArmed {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                    Text("Listening")
                        .font(.headline)
                    Text("\(gesture.displayName) \(session.count(for: gesture) + 1) of \(session.repetitions)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                // One dot for each tap of the gesture, filled as Sidetap hears it.
                HStack(spacing: 12) {
                    ForEach(0..<gesture.rawValue, id: \.self) { index in
                        Circle()
                            .fill(index < session.attempt.taps.count ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Taps heard")
                .accessibilityValue("\(session.attempt.taps.count) of \(gesture.rawValue)")
            } else {
                Text("Sidetap ignores all sounds until you start listening.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Start Listening") {
                    model.armCalibration()
                }
                .sidetapPrimaryButton()
                .controlSize(.large)
                .disabled(!model.audio.isListening)
                .help(model.audio.isListening ? "Start collecting this gesture" : "Resume the microphone first")
                .accessibilityHint(model.audio.isListening
                    ? "Starts listening for this gesture."
                    : "The microphone is paused. Resume it first.")
            }

            if let guidance = model.calibrationGuidance {
                Label(guidance, systemImage: "arrow.counterclockwise.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Capture guidance: \(guidance)")
            } else if let quality = model.audio.diagnostics.latestSignalQuality {
                HStack(spacing: 18) {
                    Label(quality.summary, systemImage: quality.score > 0.48 ? "checkmark.circle" : "exclamationmark.circle")
                    Text(String(format: "%.1f dB SNR", quality.signalToNoiseDB))
                    Text(String(format: "%.3f peak", quality.peakAmplitude))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Signal quality")
                .accessibilityValue("\(quality.summary). \(String(format: "%.1f", quality.signalToNoiseDB)) decibels signal to noise.")
            }

            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    model.undoLastCalibrationGesture()
                }
                .sidetapSecondaryButton()
                .disabled(session.gestures.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel) {
                    model.cancelCalibration()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func completionControls(_ session: CalibrationSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                String(format: "Gestures allow up to %.2f seconds between taps, based on your pace.", session.maximumTapGap),
                systemImage: "metronome"
            )
            .font(.callout)

            HStack {
                Button("Save and Set Actions") {
                    model.finishCalibration(openActions: true)
                }
                .sidetapPrimaryButton()
                .controlSize(.large)

                Button("Save for Later") {
                    model.finishCalibration()
                }
                .sidetapSecondaryButton()

                Spacer()

                Button("Cancel", role: .cancel) {
                    model.cancelCalibration()
                }
            }

            DisclosureGroup("Teach Sidetap sounds to reject (recommended)", isExpanded: $showRejectionTraining) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture Talking first: speak normally for a few seconds. Only speech peaks that reach the classifier are counted, and only acoustic features are saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(["Talking", "Typing", "Laptop touch", "Background noise"], id: \.self) { label in
                        HStack {
                            Button {
                                model.collectNegativeExamples(label: session.negativeLabel == label ? nil : label)
                            } label: {
                                Label(
                                    session.negativeLabel == label ? "Stop \(label)" : "Capture \(label)",
                                    systemImage: session.negativeLabel == label ? "stop.circle.fill" : "record.circle"
                                )
                            }
                            .sidetapSecondaryButton()
                            .disabled(!model.audio.isListening)
                            Text("\(session.negativeCount(for: label)) captured")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(session.negativeCount(for: label)) \(label) examples captured")
                            if session.negativeCount(for: label) > 0 {
                                Button("Clear") {
                                    model.clearNegativeExamples(label: label)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Clear \(label) examples")
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func instruction(for session: CalibrationSession) -> String {
        guard let gesture = session.currentGesture else { return "" }
        let verb = gesture == .double ? "Double-tap" : "Triple-tap"
        if session.isArmed {
            return "\(verb) the way you will in everyday use. Wait for the count to go up before the next one."
        }
        return "\(verb) \(session.repetitions) times, with a pause after each one."
    }
}
