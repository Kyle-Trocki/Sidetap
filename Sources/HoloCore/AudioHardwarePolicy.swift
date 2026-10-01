import Foundation

public struct AudioEndpointInfo: Codable, Equatable, Sendable {
    public var name: String
    public var isBuiltIn: Bool

    public init(name: String, isBuiltIn: Bool) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public struct AudioRouteInfo: Codable, Equatable, Sendable {
    public var input: AudioEndpointInfo?
    public var output: AudioEndpointInfo?

    public init(input: AudioEndpointInfo?, output: AudioEndpointInfo?) {
        self.input = input
        self.output = output
    }
}

public enum AudioHardwarePolicyIssue: Equatable, Sendable {
    case inputUnavailable
    case builtInInputRequired(selected: String)
    case outputUnavailable
    case builtInOutputRequired(selected: String)
}

public enum AudioHardwarePolicy {
    /// Sidetap always requires the built-in microphone. Active and hybrid sensing also
    /// require built-in output because they emit a measurement probe.
    public static func issue(
        for route: AudioRouteInfo,
        strategy: SensingStrategy
    ) -> AudioHardwarePolicyIssue? {
        guard let input = route.input else { return .inputUnavailable }
        guard input.isBuiltIn else { return .builtInInputRequired(selected: input.name) }

        guard strategy != .passive else { return nil }
        guard let output = route.output else { return .outputUnavailable }
        guard output.isBuiltIn else { return .builtInOutputRequired(selected: output.name) }
        return nil
    }
}
