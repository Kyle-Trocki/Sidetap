import AppKit
import SwiftUI

final class SidetapAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS leaves the cursor in a text field when you click elsewhere in its
        // window. Here, a click anywhere outside that field gives the cursor up.
        _ = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            // A field that is being edited has a text view as the first responder.
            // Hit-testing can't find it: SwiftUI's hosting view answers for its controls.
            if let editor = event.window?.firstResponder as? NSText,
               !editor.convert(editor.bounds, to: nil).contains(event.locationInWindow) {
                event.window?.makeFirstResponder(nil)
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SidetapApp: App {
    @NSApplicationDelegateAdaptor(SidetapAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Sidetap", id: "main") {
            RootView(model: model)
                .frame(minWidth: 840, minHeight: 680)
                .task { await model.activateOnLaunch() }
        }
        .defaultSize(width: 980, height: 760)
        .commands {
            CommandMenu("Sidetap") {
                if model.profile == nil && model.calibrationSession == nil {
                    Button("Set Up") {
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
                .disabled(model.profile == nil || model.calibrationSession != nil)
            }
        }
    }
}
