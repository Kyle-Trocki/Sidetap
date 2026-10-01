import XCTest
@testable import SidetapCore

final class LocalActionPlannerTests: XCTestCase {
    func testVisualAndIncompleteActionsProduceNoCommand() {
        XCTAssertEqual(ZoneActionConfiguration().kind, .none)
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .none)))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .copyText, text: "  ")))
        // Paste text with no text still acts: it pastes the current pasteboard.
        XCTAssertEqual(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .pasteText, text: "  ")), .pasteText(""))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .speakText, text: "\n")))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .runShortcut, text: "")))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .openApplication)))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .openItem)))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .runShellCommand, text: "  ")))
    }

    func testSoundAndTextCommandsPreserveConfiguredContent() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .sound, soundName: " Tink ")),
            .playSound(name: "Tink")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .copyText, text: " Focus mode ")),
            .copyText(" Focus mode ")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .pasteText, text: "On my way")),
            .pasteText("On my way")
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .speakText, text: "Done")),
            .speakText("Done")
        )
    }

    func testWebsiteCommandDefaultsToHTTPSAndRejectsUnsafeSchemes() throws {
        let command = try XCTUnwrap(LocalActionPlanner.command(for: ZoneActionConfiguration(
            kind: .openURL,
            text: "example.com/path"
        )))
        XCTAssertEqual(command, .openURL(try XCTUnwrap(URL(string: "https://example.com/path"))))

        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(
            kind: .openURL,
            text: "file:///tmp/secret"
        )))
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(
            kind: .openURL,
            text: "https://"
        )))
    }

    func testShortcutNameIsEncodedAsAQueryValue() throws {
        let command = try XCTUnwrap(LocalActionPlanner.command(for: ZoneActionConfiguration(
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
            LocalActionPlanner.command(for: ZoneActionConfiguration(
                kind: .openApplication,
                bookmarkData: bookmark
            )),
            .openApplication(bookmarkData: bookmark)
        )
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(
            kind: .openApplication,
            bookmarkData: Data()
        )))
    }

    func testFileAndFolderCommandRequiresNonemptyBookmarkData() {
        let bookmark = Data([0x46, 0x49, 0x4C, 0x45])
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(
                kind: .openItem,
                bookmarkData: bookmark
            )),
            .openItem(bookmarkData: bookmark)
        )
    }

    func testShellCommandIsTrimmedAndRejectsNullBytes() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(
                kind: .runShellCommand,
                text: "  open -a Claude  "
            )),
            .runShellCommand("open -a Claude")
        )
        XCTAssertNil(LocalActionPlanner.command(for: ZoneActionConfiguration(
            kind: .runShellCommand,
            text: "echo before\0after"
        )))
    }

    func testScreenshotCommandsNeedNoAdditionalConfiguration() {
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .screenshotClipboard)),
            .takeScreenshot(interactive: false, destination: .desktop)
        )
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .screenshotSelection)),
            .takeScreenshot(interactive: true, destination: .desktop)
        )
        // The destination is the action's text; anything unrecognized saves to the Desktop.
        for destination in ScreenshotDestination.allCases {
            XCTAssertEqual(
                LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .screenshotSelection, text: destination.rawValue)),
                .takeScreenshot(interactive: true, destination: destination)
            )
        }
        XCTAssertEqual(
            LocalActionPlanner.command(for: ZoneActionConfiguration(kind: .screenshotClipboard, text: "leftover text")),
            .takeScreenshot(interactive: false, destination: .desktop)
        )
    }

    func testAutomaticDispatchRequiresAcceptedDecisionOnDesk() {
        let accepted = ClassificationDecision(
            zone: .rightTop,
            confidence: 0.9,
            signalStrength: 0.8,
            zoneDistances: [],
            rejectionReason: nil
        )
        let rejected = ClassificationDecision(
            zone: nil,
            confidence: 0.2,
            signalStrength: 0.3,
            zoneDistances: [],
            rejectionReason: .ambiguousZone
        )

        XCTAssertTrue(LocalActionDispatchPolicy.allowsAutomaticDispatch(
            for: accepted,
            isDeskActive: true
        ))
        XCTAssertFalse(LocalActionDispatchPolicy.allowsAutomaticDispatch(
            for: accepted,
            isDeskActive: false
        ))
        XCTAssertFalse(LocalActionDispatchPolicy.allowsAutomaticDispatch(
            for: rejected,
            isDeskActive: true
        ))
    }
}
