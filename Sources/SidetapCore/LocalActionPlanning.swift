import Foundation

public enum LocalActionCommand: Equatable, Sendable {
    case playSound(name: String)
    case copyText(String)
    /// Empty text means paste whatever is already on the pasteboard.
    case pasteText(String)
    case speakText(String)
    case openURL(URL)
    case runShortcut(URL)
    case openApplication(bookmarkData: Data)
    case openItem(bookmarkData: Data)
    case runShellCommand(String)
    case takeScreenshot(interactive: Bool, destination: ScreenshotDestination)
    case pressKeys(keyCode: UInt16, modifiers: UInt64)
    case pressMediaKey(MediaKey)
}

public enum LocalActionPlanner {
    /// Converts a saved action into a validated side-effect command. `nil`
    /// means visual feedback only or an action that is not fully configured.
    public static func command(for action: ActionConfiguration) -> LocalActionCommand? {
        switch action.kind {
        case .none:
            return nil

        case .sound:
            let name = action.soundName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .playSound(name: name)

        case .copyText:
            return hasContent(action.text) ? .copyText(action.text) : nil

        case .pasteText:
            return .pasteText(hasContent(action.text) ? action.text : "")

        case .speakText:
            return hasContent(action.text) ? .speakText(action.text) : nil

        case .openURL:
            var candidate = action.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return nil }
            if !candidate.contains("://") { candidate = "https://" + candidate }
            guard let url = URL(string: candidate),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false else { return nil }
            return .openURL(url)

        case .runShortcut:
            let name = action.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            return components.url.map(LocalActionCommand.runShortcut)

        case .openApplication:
            guard let bookmarkData = action.bookmarkData, !bookmarkData.isEmpty else { return nil }
            return .openApplication(bookmarkData: bookmarkData)

        case .openItem:
            guard let bookmarkData = action.bookmarkData, !bookmarkData.isEmpty else { return nil }
            return .openItem(bookmarkData: bookmarkData)

        case .runShellCommand:
            let command = action.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty, !command.contains("\0") else { return nil }
            return .runShellCommand(command)

        case .screenshotClipboard, .screenshotSelection:
            return .takeScreenshot(
                interactive: action.kind == .screenshotSelection,
                destination: ScreenshotDestination(rawValue: action.text) ?? .desktop
            )

        case .pressKeys:
            guard let keyCode = action.keyCode else { return nil }
            return .pressKeys(keyCode: keyCode, modifiers: action.keyModifiers ?? 0)

        case .mediaKey:
            return .pressMediaKey(MediaKey(rawValue: action.text) ?? .playPause)
        }
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
