import XCTest
@testable import YeelightBar

final class CommandRateLimiterTests: XCTestCase {
    func testCalculatesDelayWithoutSleeping() async {
        let limiter = CommandRateLimiter(minimumInterval: 0.5)

        let first = await limiter.delayForNextSend(now: 1_000)
        let second = await limiter.delayForNextSend(now: 1_000)
        let third = await limiter.delayForNextSend(now: 600_000_001)

        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 500_000_000)
        XCTAssertEqual(third, 400_000_999)
    }

    func testEnforcesPerConnectionRollingMinuteQuota() async {
        let limiter = CommandRateLimiter(minimumInterval: 0, window: 60)
        let connectionID = UUID()

        for _ in 0..<CommandRateLimiter.perConnectionLimit {
            let delay = await limiter.delayForCommand(connectionID: connectionID, now: 1_000)
            XCTAssertEqual(delay, 0)
        }

        let limitedDelay = await limiter.delayForCommand(connectionID: connectionID, now: 1_000)
        XCTAssertEqual(limitedDelay, 60_000_000_000)
    }

    func testEnforcesGlobalRollingMinuteQuotaAcrossConnections() async {
        let limiter = CommandRateLimiter(minimumInterval: 0, window: 60)

        for _ in 0..<CommandRateLimiter.globalLimit {
            let delay = await limiter.delayForCommand(connectionID: UUID(), now: 1_000)
            XCTAssertEqual(delay, 0)
        }

        let limitedDelay = await limiter.delayForCommand(connectionID: UUID(), now: 1_000)
        XCTAssertEqual(limitedDelay, 60_000_000_000)
    }

    func testCancellationStopsRateLimitWait() async {
        let limiter = CommandRateLimiter(minimumInterval: 0, window: 60)
        let connectionID = UUID()
        for _ in 0..<CommandRateLimiter.perConnectionLimit {
            _ = await limiter.delayForCommand(connectionID: connectionID, now: 1_000)
        }

        let task = Task {
            try await limiter.waitTurn(connectionID: connectionID, now: 1_000)
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
