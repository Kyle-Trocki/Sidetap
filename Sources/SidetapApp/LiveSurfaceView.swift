import SidetapCore
import SwiftUI

struct LiveSurfaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.selectedProfile == nil {
            setupPrompt
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(36)
                .background(SidetapTheme.background)
        } else {
            liveDesk
        }
    }

    private var liveDesk: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            gesturePanel
                .frame(maxWidth: 760, maxHeight: 490)
                .padding(.horizontal, 36)

            resultStrip

            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .background(SidetapTheme.background)
    }

    private var gesturePanel: some View {
        VStack(spacing: 22) {
            Image(systemName: model.audio.isListening ? "hand.tap.fill" : "hand.tap")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(model.pendingTapCount > 0 ? Color.accentColor : Color.secondary)
            Text(gestureTitle)
                .font(.largeTitle.weight(.semibold))
            VStack(spacing: 10) {
                ForEach(model.selectedProfile?.gestures ?? []) { gesture in
                    HStack {
                        Text(gesture.displayName)
                            .fontWeight(model.lastGesture == gesture ? .semibold : .regular)
                        Spacer()
                        Text(model.selectedProfile?.action(for: gesture).kind.displayName ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var gestureTitle: String {
        switch model.pendingTapCount {
        case 0: return model.lastGesture?.displayName ?? "Tap twice or more"
        case 1: return "1 tap…"
        default: return "\(model.pendingTapCount) taps…"
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Set up the desk around your MacBook")
                .font(.title2.weight(.semibold))
            Text("Taps cannot be assigned until Sidetap learns this desk. You will tap ten times across each of four broad zones: rear and front on both sides of the MacBook.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Microphone access is requested when calibration begins.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Set Up Four Zones") {
                model.openSetup()
            }
            .sidetapPrimaryButton()
            .controlSize(.large)
        }
        .padding(.top, 4)
    }

    private var resultStrip: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lastResultTitle)
                    .font(.headline)
                Text(lastResultDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 170, alignment: .leading)

            Divider().frame(height: 34)

            compactGauge("Confidence", value: model.lastDecision?.confidence ?? 0)
            compactGauge("Signal", value: model.lastDecision?.signalStrength ?? model.audio.liveLevel)

            if let latency = model.lastDecision?.processingLatencyMilliseconds, latency > 0 {
                Divider().frame(height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f ms", latency))
                        .font(.callout.monospacedDigit())
                    Text("Processing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Recalibrate", systemImage: "arrow.triangle.2.circlepath") {
                model.prepareRecalibration()
            }
            .sidetapSecondaryButton()
        }
        .padding(16)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lastResultDetail: String {
        if let decision = model.lastDecision, !decision.isTap, let reason = decision.rejectionReason {
            return reason.displayName
        }
        return model.selectedProfile?.name ?? ""
    }

    private var lastResultTitle: String {
        guard let decision = model.lastDecision else { return "Waiting for taps" }
        return decision.isTap ? "Tap heard" : "Sound rejected"
    }

    private func compactGauge(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: value)
                .frame(width: 112)
        }
    }
}
