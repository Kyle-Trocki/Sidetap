import SidetapCore
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    private let diagnosticLabels = ["Tap", "Talking", "Typing", "Laptop touch", "Background noise"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Diagnostics")
                    .font(.title.weight(.semibold))
                Text("Inspect the microphone path and capture labeled examples.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Microphone") {
                    if let route = model.audio.diagnostics.audioRoute {
                        LabeledContent("Input", value: endpointDescription(route.input))
                        LabeledContent("Output", value: endpointDescription(route.output))
                        if let issue = AudioHardwarePolicy.issue(for: route, strategy: model.targetStrategy) {
                            Label(hardwareIssueDescription(issue), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        LabeledContent("Input", value: model.audio.diagnostics.deviceName)
                    }
                    LabeledContent("Available channels", value: "\(model.audio.diagnostics.channelCount)")
                    LabeledContent("Channel names", value: model.audio.diagnostics.channelNames.joined(separator: ", "))
                    LabeledContent("Sample rate", value: String(format: "%.0f Hz", model.audio.diagnostics.sampleRate))
                    LabeledContent("Analysis buffer", value: "\(model.audio.diagnostics.bufferFrameCount) frames")
                    LabeledContent("Reported input latency", value: String(format: "%.1f ms", model.audio.diagnostics.timing.estimatedInputLatencyMilliseconds))
                    LabeledContent("Callback jitter", value: String(format: "%.2f ms", model.audio.diagnostics.timing.callbackJitterMilliseconds))
                    Label(
                        "Sidetap uses only the channels exposed by AVAudioEngine; physical microphone-array access is not assumed.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Latest detected tap") {
                    if model.audio.diagnostics.latestFrequencyResponse.isEmpty {
                        Text("Tap to inspect the response.")
                            .foregroundStyle(.secondary)
                    } else {
                        spectrumChart(model.audio.diagnostics.latestFrequencyResponse)
                            .frame(height: 150)
                            .padding(.vertical, 6)
                    }

                    if let quality = model.audio.diagnostics.latestSignalQuality {
                        LabeledContent("Quality", value: quality.summary)
                        LabeledContent("Signal-to-noise", value: String(format: "%.1f dB", quality.signalToNoiseDB))
                        LabeledContent("Peak amplitude", value: String(format: "%.3f", quality.peakAmplitude))
                        LabeledContent("Clipping", value: String(format: "%.1f%%", quality.clippingFraction * 100))
                    }
                }

                Section("Labeled capture") {
                    Picker("Label", selection: $model.diagnosticLabel) {
                        ForEach(diagnosticLabels, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }

                    HStack {
                        Button(model.diagnosticCaptureArmed ? "Waiting for Signal…" : "Capture Next Tap") {
                            model.armDiagnosticCapture()
                        }
                        .sidetapPrimaryButton()
                        .disabled(model.diagnosticCaptureArmed || !model.audio.isListening)

                        Text("\(model.diagnosticCaptures.count) feature samples")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Export JSON") { model.exportDiagnosticReport() }
                    }
                }

                Section("Privacy and debug audio") {
                    Toggle("Retain 90 ms debug recordings", isOn: Binding(
                        get: { model.debugRecordingEnabled },
                        set: model.setDebugRecordingEnabled
                    ))
                    Text(model.debugRecordingEnabled
                         ? "Raw WAV windows are being saved locally until you delete them."
                         : "Audio is discarded after feature extraction. The saved calibration contains features, not recordings.")
                        .font(.caption)
                        .foregroundStyle(model.debugRecordingEnabled ? Color.red : Color.secondary)
                    if model.hasDebugRecordings {
                        Button("Delete All Debug Recordings", role: .destructive) {
                            model.clearDebugRecordings()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: 760)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidetapTheme.background)
    }

    private func endpointDescription(_ endpoint: AudioEndpointInfo?) -> String {
        guard let endpoint else { return "Unavailable" }
        return "\(endpoint.name) · \(endpoint.isBuiltIn ? "Built-in" : "External")"
    }

    private func hardwareIssueDescription(_ issue: AudioHardwarePolicyIssue) -> String {
        switch issue {
        case .inputUnavailable:
            return "The built-in microphone is unavailable."
        case .builtInInputRequired(let selected):
            return "Sidetap can't find the built-in microphone. The default input is \(selected)."
        case .outputUnavailable:
            return "This sensing approach requires the built-in speakers, which are unavailable."
        case .builtInOutputRequired(let selected):
            return "Active sensing can't find the built-in speakers. The default output is \(selected)."
        }
    }

    private func spectrumChart(_ bands: [SpectrumBand]) -> some View {
        GeometryReader { geometry in
            let count = max(bands.count, 1)
            let width = geometry.size.width / CGFloat(count)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bands) { band in
                    let normalized = min(max((band.levelDB + 110) / 90, 0.015), 1)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(width - 3, 2), height: geometry.size.height * normalized)
                        .help(String(format: "%.0f Hz • %.1f dB", band.centerFrequency, band.levelDB))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityLabel("Frequency response of latest detected tap")
    }
}
