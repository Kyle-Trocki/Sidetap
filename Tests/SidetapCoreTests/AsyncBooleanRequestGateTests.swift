import XCTest
@testable import SidetapCore

final class AsyncBooleanRequestGateTests: XCTestCase {
    func testConcurrentCallersShareOneInFlightRequest() async {
        let gate = AsyncBooleanRequestGate()
        let counter = RequestCounter()

        async let first = gate.run {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        }
        async let second = gate.run {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        }

        let results = await [first, second]
        let requestCount = await counter.value

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(requestCount, 1)
    }
}

private actor RequestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
