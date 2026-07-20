import Foundation

actor CommandRateLimiter {
    static let perConnectionLimit = 60
    static let globalLimit = 144

    private let minimumInterval: UInt64
    private let window: UInt64
    private var nextAllowedSendTime: UInt64 = 0
    private var globalReservations: [UInt64] = []
    private var connectionReservations: [UUID: [UInt64]] = [:]

    init(minimumInterval: TimeInterval = 0.12, window: TimeInterval = 60) {
        self.minimumInterval = UInt64(minimumInterval * 1_000_000_000)
        self.window = UInt64(window * 1_000_000_000)
    }

    /// Reserves a command slot using Yeelight's rolling one-minute quotas.
    /// Cancellation propagates to the caller instead of allowing a stale command to continue.
    func waitTurn(
        connectionID: UUID,
        now: @autoclosure () -> UInt64 = DispatchTime.now().uptimeNanoseconds
    ) async throws {
        let current = now()
        let delay = reserveDelay(connectionID: connectionID, now: current)
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        try Task.checkCancellation()
    }

    /// Retained as a deterministic minimum-interval primitive for unit tests.
    func delayForNextSend(now: UInt64) -> UInt64 {
        if now < nextAllowedSendTime {
            let delay = nextAllowedSendTime - now
            nextAllowedSendTime += minimumInterval
            return delay
        }

        nextAllowedSendTime = now + minimumInterval
        return 0
    }

    func delayForCommand(connectionID: UUID, now: UInt64) -> UInt64 {
        reserveDelay(connectionID: connectionID, now: now)
    }

    private func reserveDelay(connectionID: UUID, now: UInt64) -> UInt64 {
        pruneReservations(now: now)

        var reservation = max(now, nextAllowedSendTime)
        let perConnection = connectionReservations[connectionID, default: []]

        if perConnection.count >= Self.perConnectionLimit {
            let constrainedByConnection = perConnection[perConnection.count - Self.perConnectionLimit] + window
            reservation = max(reservation, constrainedByConnection)
        }

        if globalReservations.count >= Self.globalLimit {
            let constrainedGlobally = globalReservations[globalReservations.count - Self.globalLimit] + window
            reservation = max(reservation, constrainedGlobally)
        }

        nextAllowedSendTime = reservation + minimumInterval
        globalReservations.append(reservation)
        connectionReservations[connectionID, default: []].append(reservation)
        return reservation > now ? reservation - now : 0
    }

    private func pruneReservations(now: UInt64) {
        let cutoff = now > window ? now - window : 0
        globalReservations.removeAll { $0 <= cutoff }

        for id in Array(connectionReservations.keys) {
            connectionReservations[id]?.removeAll { $0 <= cutoff }
            if connectionReservations[id]?.isEmpty == true {
                connectionReservations.removeValue(forKey: id)
            }
        }
    }
}
