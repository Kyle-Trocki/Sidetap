import XCTest
@testable import SidetapCore

final class AudioHardwarePolicyTests: XCTestCase {
    private let builtInInput = AudioEndpointInfo(name: "MacBook Pro Microphone", isBuiltIn: true)
    private let builtInOutput = AudioEndpointInfo(name: "MacBook Pro Speakers", isBuiltIn: true)
    private let externalInput = AudioEndpointInfo(name: "USB Microphone", isBuiltIn: false)
    private let externalOutput = AudioEndpointInfo(name: "AirPods", isBuiltIn: false)

    func testBuiltInRouteSupportsEveryStrategy() {
        let route = AudioRouteInfo(input: builtInInput, output: builtInOutput)

        for strategy in SensingStrategy.allCases {
            XCTAssertNil(AudioHardwarePolicy.issue(for: route, strategy: strategy))
        }
    }

    func testExternalInputIsRejectedForPassiveSensing() {
        let issue = AudioHardwarePolicy.issue(
            for: AudioRouteInfo(input: externalInput, output: builtInOutput),
            strategy: .passive
        )

        XCTAssertEqual(issue, .builtInInputRequired(selected: "USB Microphone"))
    }

    func testPassiveSensingDoesNotRequireSpeakerOutput() {
        let route = AudioRouteInfo(input: builtInInput, output: nil)
        XCTAssertNil(AudioHardwarePolicy.issue(for: route, strategy: .passive))
    }

    func testActiveAndHybridRejectExternalOutput() {
        let route = AudioRouteInfo(input: builtInInput, output: externalOutput)

        XCTAssertEqual(
            AudioHardwarePolicy.issue(for: route, strategy: .active),
            .builtInOutputRequired(selected: "AirPods")
        )
        XCTAssertEqual(
            AudioHardwarePolicy.issue(for: route, strategy: .hybrid),
            .builtInOutputRequired(selected: "AirPods")
        )
    }

    func testMissingInputAndRequiredOutputAreReported() {
        XCTAssertEqual(
            AudioHardwarePolicy.issue(
                for: AudioRouteInfo(input: nil, output: builtInOutput),
                strategy: .passive
            ),
            .inputUnavailable
        )
        XCTAssertEqual(
            AudioHardwarePolicy.issue(
                for: AudioRouteInfo(input: builtInInput, output: nil),
                strategy: .active
            ),
            .outputUnavailable
        )
    }
}
