import AppKit
import AVFoundation
import Foundation
import HoloCore

enum LocalActionDispatchError: Error, LocalizedError {
    case soundUnavailable(String)
    case pasteboardWriteFailed
    case accessibilityRequired
    case openFailed(String)
    case applicationBookmarkInvalid
    case itemBookmarkInvalid
    case automationFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .soundUnavailable(let name):
            return "The system sound “\(name)” is unavailable."
        case .pasteboardWriteFailed:
            return "Sidetap could not write the assigned text to the pasteboard."
        case .accessibilityRequired:
            return "Paste text needs Accessibility access to press ⌘V for you. Turn on Sidetap in System Settings › Privacy & Security › Accessibility, then try again."
        case .openFailed(let destination):
            return "macOS could not open \(destination)."
        case .applicationBookmarkInvalid:
            return "The assigned application is no longer available. Choose it again in Actions."
        case .itemBookmarkInvalid:
            return "The assigned file or folder is no longer available. Choose it again in Actions."
        case .automationFailed(let name, let status):
            return "\(name) exited with status \(status). Check the action and Sidetap's macOS permissions."
        }
    }
}

@MainActor
final class LocalActionDispatcher {
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var runningProcesses: [UUID: Process] = [:]
    var onAsyncError: ((Error) -> Void)?

    func perform(_ action: ZoneActionConfiguration) throws {
        guard let command = LocalActionPlanner.command(for: action) else { return }
        switch command {
        case .playSound(let name):
            guard let sound = NSSound(named: NSSound.Name(name)), sound.play() else {
                throw LocalActionDispatchError.soundUnavailable(name)
            }
        case .copyText(let text):
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                throw LocalActionDispatchError.pasteboardWriteFailed
            }
        case .pasteText(let text):
            // Sending ⌘V to another app needs Accessibility access. The request
            // adds Sidetap to that list in System Settings the first time.
            guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
                throw LocalActionDispatchError.accessibilityRequired
            }
            let pasteboard = NSPasteboard.general
            // With assigned text, borrow the pasteboard for it; with none, paste what's there.
            var previousItems: [NSPasteboardItem]?
            if !text.isEmpty {
                previousItems = (pasteboard.pasteboardItems ?? []).map { item in
                    let copy = NSPasteboardItem()
                    for type in item.types {
                        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                    }
                    return copy
                }
                pasteboard.clearContents()
                guard pasteboard.setString(text, forType: .string) else {
                    throw LocalActionDispatchError.pasteboardWriteFailed
                }
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: keyDown)  // V
                event?.flags = .maskCommand
                event?.post(tap: .cgSessionEventTap)
            }
            if let previousItems {
                // Put the previous clipboard back once the frontmost app has read the text.
                // ponytail: a fixed 0.5 s wait; an app slower than that pastes the old clipboard.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(previousItems)
                }
            }
        case .speakText(let text):
            speechSynthesizer.stopSpeaking(at: .immediate)
            speechSynthesizer.speak(AVSpeechUtterance(string: text))
        case .openURL(let url), .runShortcut(let url):
            guard NSWorkspace.shared.open(url) else {
                throw LocalActionDispatchError.openFailed(url.absoluteString)
            }
        case .openApplication(let bookmarkData):
            let url = try resolveBookmark(bookmarkData, invalidError: .applicationBookmarkInvalid)
            let accessing = url.startAccessingSecurityScopedResource()
            guard accessing else {
                throw LocalActionDispatchError.applicationBookmarkInvalid
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] application, error in
                Task { @MainActor in
                    url.stopAccessingSecurityScopedResource()
                    if let error {
                        self?.onAsyncError?(error)
                    } else if application == nil {
                        self?.onAsyncError?(LocalActionDispatchError.openFailed(url.lastPathComponent))
                    }
                }
            }
        case .openItem(let bookmarkData):
            let url = try resolveBookmark(bookmarkData, invalidError: .itemBookmarkInvalid)
            let accessing = url.startAccessingSecurityScopedResource()
            guard accessing else { throw LocalActionDispatchError.itemBookmarkInvalid }
            defer { url.stopAccessingSecurityScopedResource() }
            guard NSWorkspace.shared.open(url) else {
                throw LocalActionDispatchError.openFailed(url.lastPathComponent)
            }
        case .runShellCommand(let command):
            try launchProcess(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                name: "Shell command"
            )
        case .takeScreenshot(let interactive):
            try launchProcess(
                executable: "/usr/sbin/screencapture",
                arguments: interactive ? ["-i", "-c"] : ["-x", "-c"],
                name: interactive ? "Selection capture" : "Screenshot"
            )
        }
    }

    private func resolveBookmark(
        _ data: Data,
        invalidError: LocalActionDispatchError
    ) throws -> URL {
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw invalidError
        }
        guard !stale else { throw invalidError }
        return url
    }

    private func launchProcess(
        executable: String,
        arguments: [String],
        name: String
    ) throws {
        let identifier = UUID()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                self?.runningProcesses.removeValue(forKey: identifier)
                if status != 0 {
                    self?.onAsyncError?(LocalActionDispatchError.automationFailed(name, status))
                }
            }
        }
        runningProcesses[identifier] = process
        do {
            try process.run()
        } catch {
            runningProcesses.removeValue(forKey: identifier)
            throw error
        }
    }
}

final class DebugRecordingStore {
    let directory: URL

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directory = support.appendingPathComponent("Holo/DebugCaptures", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func save(_ observation: TapObservation, label: String, sampleRate: Double) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let safeLabel = label.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(safeLabel).wav")
        try WaveFileWriter.write(channels: observation.rawChannels, sampleRate: sampleRate, to: url)
        return url
    }

    func clear() throws {
        let manager = FileManager.default
        for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: file)
        }
    }

    func containsRecordings() throws -> Bool {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return files.contains { $0.pathExtension.lowercased() == "wav" }
    }
}
