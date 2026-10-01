import Darwin
import Foundation
import SidetapCore

private func endpointDescription(_ endpoint: AudioEndpointInfo?) -> String {
    guard let endpoint else { return "Unavailable" }
    return "\(endpoint.name) [\(endpoint.isBuiltIn ? "built-in" : "external")]"
}

private func issueDescription(_ issue: AudioHardwarePolicyIssue) -> String {
    switch issue {
    case .inputUnavailable:
        return "no input device"
    case .builtInInputRequired(let selected):
        return "no built-in microphone; default is \(selected)"
    case .outputUnavailable:
        return "no output device"
    case .builtInOutputRequired(let selected):
        return "no built-in speakers; default is \(selected)"
    }
}

do {
    let route = try SystemAudioRouteInspector.currentRoute()
    print("Input:  \(endpointDescription(route.input))")
    print("Output: \(endpointDescription(route.output))")

    var hasFailure = false
    for strategy in SensingStrategy.allCases {
        if let issue = AudioHardwarePolicy.issue(for: route, strategy: strategy) {
            hasFailure = true
            print("\(strategy.displayName): unavailable — \(issueDescription(issue))")
        } else {
            print("\(strategy.displayName): ready")
        }
    }
    if hasFailure { exit(EXIT_FAILURE) }
} catch {
    FileHandle.standardError.write(Data("Route inspection failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
