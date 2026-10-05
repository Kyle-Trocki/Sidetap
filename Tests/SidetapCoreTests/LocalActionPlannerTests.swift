import XCTest
@testable import SidetapCore

final class LocalActionPlannerTests: XCTestCase {
    func testVisualAndIncompleteActionsProduceNoCommand() {
        XCTAssertEqual(ActionConfiguration().kind, .none)
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .none)))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .copyText, text: "  ")))
        // Paste text with no text still acts: it pastes the current pasteboard.
        XCTAssertEqual(LocalActionPlanner.command(for: ActionConfiguration(kind: .pasteText, text: "  ")), .pasteText(""))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .speakText, text: "\n")))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .runShortcut, text: "")))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .openApplication)))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .openItem)))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .runShellCommand, text: "  ")))
    }

    func testSoundAndTextCommandsPreserveConfiguredContent() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .sound, soundName: " Tink ")),
            .playSound(name: "Tink")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .copyText, text: " Focus mode ")),
            .copyText(" Focus mode ")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .pasteText, text: "On my way")),
            .pasteText("On my way")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .speakText, text: "Done")),
            .speakText("Done")
        )
    }

    func testWebsiteCommandDefaultsToHTTPSAndRejectsUnsafeSchemes() throws {
        let command = try XCTUnwrap(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .openURL,
            text: "example.com/path"
        )))
        XCTAssertEqual(command, .openURL(try XCTUnwrap(URL(string: "https://example.com/path"))))

        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .openURL,
            text: "file:///tmp/secret"
        )))
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .openURL,
            text: "https://"
        )))
    }

    func testShortcutNameIsEncodedAsAQueryValue() throws {
        let command = try XCTUnwrap(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .runShortcut,
            text: "Focus & Work"
        )))
        guard case .runShortcut(let url) = command else {
            return XCTFail("Expected a Shortcut command")
        }
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "run-shortcut")
        XCTAssertEqual(components.queryItems?.first?.name, "name")
        XCTAssertEqual(components.queryItems?.first?.value, "Focus & Work")
    }

    func testApplicationCommandRequiresNonemptyBookmarkData() {
        let bookmark = Data([0x48, 0x4F, 0x4C, 0x4F])
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(
                kind: .openApplication,
                bookmarkData: bookmark
            )),
            .openApplication(bookmarkData: bookmark)
        )
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .openApplication,
            bookmarkData: Data()
        )))
    }

    func testFileAndFolderCommandRequiresNonemptyBookmarkData() {
        let bookmark = Data([0x46, 0x49, 0x4C, 0x45])
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(
                kind: .openItem,
                bookmarkData: bookmark
            )),
            .openItem(bookmarkData: bookmark)
        )
    }

    func testShellCommandIsTrimmedAndRejectsNullBytes() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(
                kind: .runShellCommand,
                text: "  open -a Claude  "
            )),
            .runShellCommand("open -a Claude")
        )
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(
            kind: .runShellCommand,
            text: "echo before\0after"
        )))
    }

    func testScreenshotCommandsNeedNoAdditionalConfiguration() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .screenshotClipboard)),
            .takeScreenshot(interactive: false, destination: .desktop)
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .screenshotSelection)),
            .takeScreenshot(interactive: true, destination: .desktop)
        )
        // The destination is the action's text; anything unrecognized saves to the Desktop.
        for destination in ScreenshotDestination.allCases {
            XCTAssertEqual(
                LocalActionPlanner.command(for: ActionConfiguration(kind: .screenshotSelection, text: destination.rawValue)),
                .takeScreenshot(interactive: true, destination: destination)
            )
        }
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .screenshotClipboard, text: "leftover text")),
            .takeScreenshot(interactive: false, destination: .desktop)
        )
    }

    func testKeyboardShortcutNeedsARecordedKeyAndMediaControlDefaultsToPlayOrPause() {
        // The label alone isn't a shortcut; the key code is.
        XCTAssertNil(LocalActionPlanner.command(for: ActionConfiguration(kind: .pressKeys, text: "⌘K")))
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .pressKeys, keyCode: 40, keyModifiers: 0x100000)),
            .pressKeys(keyCode: 40, modifiers: 0x100000)
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .mediaKey, text: MediaKey.mute.rawValue)),
            .pressMediaKey(.mute)
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ActionConfiguration(kind: .mediaKey, text: "leftover text")),
            .pressMediaKey(.playPause)
        )
    }
}
