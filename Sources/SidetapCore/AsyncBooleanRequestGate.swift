import Foundation

/// Shares one in-flight asynchronous decision among every concurrent caller.
/// This is used for system authorization requests, where issuing the same prompt
/// more than once is both confusing and can create duplicate downstream work.
public actor AsyncBooleanRequestGate {
    private var inFlight: Task<Bool, Never>?

    public init() {}

    public func run(
        _ operation: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        if let inFlight {
            return await inFlight.value
        }

        let task = Task { await operation() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
