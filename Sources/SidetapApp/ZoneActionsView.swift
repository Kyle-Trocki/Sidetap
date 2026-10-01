import AppKit
import SidetapCore
import SwiftUI
import UniformTypeIdentifiers

struct ZoneActionsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let profile = model.selectedProfile {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Assign actions")
                            .font(.title.weight(.semibold))
                        Text("Double-tap or triple-tap anywhere on the desk to run an action. Changes save automatically.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Form {
                        Section("Gestures") {
                            ForEach(TapGesture.allCases) { gesture in
                                ZoneActionRow(
                                    title: gesture.displayName,
                                    action: profile.action(for: gesture),
                                    onChange: { action in
                                        model.updateAction(for: gesture, action: action)
                                    },
                                    onTest: model.testAction,
                                    onError: { error in
                                        model.errorMessage = "The action could not be assigned. \(error.localizedDescription)"
                                    }
                                )
                                .id("\(profile.id)-\(gesture.rawValue)")
                            }
                        }

                        Section("Automation") {
                            Label("Use Run Shortcut for multi-step workflows such as opening Claude and starting a voice workflow.", systemImage: "command")
                            Label("Shell commands run through /bin/zsh with Sidetap's current macOS permissions.", systemImage: "terminal")
                            Label("Screenshot actions save to the Desktop, copy to the clipboard, or both, and may request Screen Recording access.", systemImage: "camera.viewfinder")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Section {
                            HStack {
                                Text("Profile: \(profile.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Delete Profile", role: .destructive) {
                                    confirmDelete = true
                                }
                            }
                        }
                    }

                    .formStyle(.grouped)
                }
                .frame(maxWidth: 780, alignment: .leading)
                .padding(36)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Desk Profile", systemImage: "macbook")
                } description: {
                    Text("Calibrate the four zones before assigning actions.")
                } actions: {
                    Button("Open Calibration") { model.section = .calibrate }
                        .sidetapPrimaryButton()
                }
            }
        }
        .background(SidetapTheme.background)
        .confirmationDialog("Delete this desk profile?", isPresented: $confirmDelete) {
            Button("Delete Profile", role: .destructive) { model.deleteSelectedProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved calibration and its actions will be removed.")
        }
    }
}

private struct ZoneActionRow: View {
    let title: String
    let onChange: (ZoneActionConfiguration) -> Bool
    let onTest: (ZoneActionConfiguration) -> Void
    let onError: (Error) -> Void
    @State private var action: ZoneActionConfiguration
    @State private var isRevertingFailedSave = false

    private let sounds = ["Tink", "Pop", "Ping", "Glass", "Funk", "Morse", "Purr", "Sosumi"]

    init(
        title: String,
        action: ZoneActionConfiguration,
        onChange: @escaping (ZoneActionConfiguration) -> Bool,
        onTest: @escaping (ZoneActionConfiguration) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.title = title
        self.onChange = onChange
        self.onTest = onTest
        self.onError = onError
        _action = State(initialValue: action)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                Picker("Action", selection: $action.kind) {
                    ForEach(ZoneActionKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .accessibilityLabel("Action for \(title)")

                detailControl
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Test", systemImage: "play.fill") {
                    onTest(action)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!canTest)
                .help(canTest ? "Test this action" : "Finish configuring this action before testing")
                .accessibilityLabel("Test action for \(title)")
            }
        } label: {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 86, alignment: .leading)
        }
        .padding(.vertical, 4)
        .onChange(of: action) { oldValue, newValue in
            if isRevertingFailedSave {
                isRevertingFailedSave = false
                return
            }
            if !onChange(newValue) {
                isRevertingFailedSave = true
                action = oldValue
            }
        }
    }

    private var canTest: Bool {
        LocalActionPlanner.command(for: action) != nil
    }

    @ViewBuilder
    private var detailControl: some View {
        switch action.kind {
        case .none:
            Text("Highlight only")
                .foregroundStyle(.secondary)
        case .sound:
            Picker("Sound", selection: $action.soundName) {
                ForEach(sounds, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityLabel("Sound to play")
        case .copyText:
            TextField("Text to copy", text: $action.text)
        case .pasteText:
            TextField("Text to paste", text: $action.text, prompt: Text("Leave empty to paste the clipboard"))
        case .speakText:
            TextField("Words to speak", text: $action.text)
        case .openURL:
            TextField("Website address", text: $action.text, prompt: Text("https://example.com"))
        case .runShortcut:
            TextField("Shortcut name", text: $action.text, prompt: Text("Start Claude listening"))
        case .openApplication:
            Button {
                chooseApplication()
            } label: {
                Label(action.text.isEmpty ? "Choose Application…" : action.text, systemImage: "app")
                    .lineLimit(1)
            }
            .sidetapSecondaryButton()
        case .openItem:
            Button {
                chooseItem()
            } label: {
                Label(action.text.isEmpty ? "Choose File or Folder…" : action.text, systemImage: "doc")
                    .lineLimit(1)
            }
            .sidetapSecondaryButton()
        case .runShellCommand:
            VStack(alignment: .leading, spacing: 3) {
                TextField("Shell command", text: $action.text, prompt: Text("open -a Claude"))
                    .font(.system(.body, design: .monospaced))
                Text("Runs automatically after an accepted tap")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        case .screenshotClipboard, .screenshotSelection:
            Picker("Save to", selection: Binding(
                get: { ScreenshotDestination(rawValue: action.text) ?? .desktop },
                set: { action.text = $0.rawValue }
            )) {
                ForEach(ScreenshotDestination.allCases) { destination in
                    Text(destination.displayName).tag(destination)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityLabel("Where the screenshot goes")
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Assign"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBookmark(for: url, displayName: url.deletingPathExtension().lastPathComponent)
    }

    private func chooseItem() {
        let panel = NSOpenPanel()
        panel.title = "Choose a file or folder"
        panel.prompt = "Assign"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBookmark(for: url, displayName: url.lastPathComponent)
    }

    private func saveBookmark(for url: URL, displayName: String) {
        do {
            action.bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            action.text = displayName
        } catch {
            action.bookmarkData = nil
            action.text = ""
            onError(error)
        }
    }
}
