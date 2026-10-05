import AppKit
import AVFoundation
import Foundation
import IOKit.hidsystem
import SidetapCore

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
            return "This action needs Accessibility access to press keys for you. Turn on Sidetap in System Settings › Privacy & Security › Accessibility, then try again."
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
            try requirePostEventAccess()
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
            pressKey(0x09, flags: .maskCommand)  // V
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
        case .takeScreenshot(let interactive, let destination):
            let path = destination == .clipboard ? nil : Self.desktopScreenshotPath()
            // screencapture writes to a file or the clipboard, not both, so for both,
            // copy the saved image. A cancelled selection leaves no file and copies nothing.
            let copySavedImage: @MainActor () -> Void = {
                guard let path, let image = NSImage(contentsOfFile: path) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            try launchProcess(
                executable: "/usr/sbin/screencapture",
                arguments: [interactive ? "-i" : "-x", path ?? "-c"],
                name: interactive ? "Selection capture" : "Screenshot",
                onSuccess: destination == .both ? copySavedImage : nil
            )
        case .pressKeys(let keyCode, let modifiers):
            try requirePostEventAccess()
            pressKey(keyCode, flags: CGEventFlags(rawValue: modifiers))
        case .pressMediaKey(let key):
            try requirePostEventAccess()
            let keyType: Int32
            switch key {
            case .playPause: keyType = NX_KEYTYPE_PLAY
            case .nextTrack: keyType = NX_KEYTYPE_NEXT
            case .previousTrack: keyType = NX_KEYTYPE_PREVIOUS
            case .volumeUp: keyType = NX_KEYTYPE_SOUND_UP
            case .volumeDown: keyType = NX_KEYTYPE_SOUND_DOWN
            case .mute: keyType = NX_KEYTYPE_MUTE
            }
            // A media key isn't an ordinary key code. The keyboard sends it as a
            // system-defined event that carries the key and its state in data1.
            for state in [0xA, 0xB] {  // Key down, then key up.
                NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: Int(keyType) << 16 | state << 8,
                    data2: -1
                )?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Sending keys to another app needs Accessibility access. The request adds
    /// Sidetap to that list in System Settings the first time.
    private func requirePostEventAccess() throws {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            throw LocalActionDispatchError.accessibilityRequired
        }
    }

    private func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cgSessionEventTap)
        }
    }

    /// A file on the real Desktop, named like the system's own screenshots.
    /// `NSHomeDirectory()` is the sandbox container, so this asks the user
    /// database for the home folder. Writing there relies on the Desktop
    /// exception in the entitlements.
    private static func desktopScreenshotPath() -> String {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(home)/Desktop/Screenshot \(formatter.string(from: Date())).png"
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
        name: String,
        onSuccess: (@MainActor () -> Void)? = nil
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
                } else {
                    onSuccess?()
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
        directory = support.appendingPathComponent("Sidetap/DebugCaptures", isDirectory: true)
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
