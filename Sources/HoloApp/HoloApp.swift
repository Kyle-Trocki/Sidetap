import AppKit
import SwiftUI

final class HoloAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct HoloApp: App {
    @NSApplicationDelegateAdaptor(HoloAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Sidetap", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1_020, minHeight: 680)
                .task { await model.activateOnLaunch() }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandMenu("Sidetap") {
                if model.selectedProfile == nil && model.guidedSection == nil {
                    Button("Set Up Desk") {
                        model.openSetup()
                    }
                } else {
                    Button(model.audio.isListening ? "Pause Listening" : "Resume Listening") {
                        model.togglePause()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }

                Button("Recalibrate") {
                    model.prepareRecalibration()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedProfile == nil || model.guidedSection != nil)
            }
        }
    }
}
