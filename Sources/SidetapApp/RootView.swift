import AppKit
import SidetapCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        content
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                statusBar
            }
            .alert("Sidetap", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
            // macOS hands the cursor to the first text field when the window becomes
            // main. Nothing is being edited then, so no field has it until you click one.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { note in
                (note.object as? NSWindow)?.makeFirstResponder(nil)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.flow {
        case nil:
            LiveSurfaceView(model: model)
        case .calibration:
            CalibrationView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { model.flow == .diagnostics },
                set: { model.flow = $0 ? .diagnostics : nil }
            )) {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            .help("Inspect the microphone path and capture labeled examples")
            // Calibration ends only through its own Save and Cancel.
            .disabled(model.flow == .calibration)

            if model.profile == nil && model.calibrationSession == nil {
                Button(action: model.openSetup) {
                    Label("Set Up", systemImage: "scope")
                }
                .help("Calibrate your taps before listening")
            } else {
                Button(action: model.togglePause) {
                    Label(
                        model.audio.isListening ? "Pause" : "Resume",
                        systemImage: model.audio.isListening ? "pause.fill" : "play.fill"
                    )
                }
                .help(model.audio.isListening ? "Pause microphone immediately" : "Resume microphone")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.audio.isListening ? "mic.fill" : "mic.slash")
                .foregroundStyle(model.audio.isListening ? .red : .secondary)
                .accessibilityLabel(model.audio.isListening ? "Microphone active" : "Microphone off")
            ProgressView(value: model.audio.liveLevel)
                .frame(width: 56)
                .accessibilityLabel("Microphone level")
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if model.audio.isListening && model.audio.strategy != .passive {
                Label("Speaker probe active", systemImage: "speaker.wave.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.debugRecordingEnabled {
                Label("Debug recording on", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if model.hasDebugRecordings {
                Label("Saved debug audio", systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Audio discarded", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(.bar)
    }
}
