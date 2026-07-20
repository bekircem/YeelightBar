import Foundation
import Network

actor YeelightConnection {
    static let maximumLogicalFrameSize = 64 * 1024

    typealias NotificationHandler = @MainActor @Sendable ([String: String]) -> Void
    typealias StateHandler = @MainActor @Sendable (NWConnection.State) -> Void

    private var connection: NWConnection?
    private var generation = UUID()
    private var receiveBuffer = Data()
    private var pending: [Int: PendingCommand] = [:]
    private var commandID = 0

    private let onNotification: NotificationHandler?
    private let onStateChanged: StateHandler?

    private struct PendingCommand {
        let completion: @Sendable (Result<YeelightIncomingMessage, Error>) -> Void
        var timeoutTask: Task<Void, Never>?
    }

    init(
        onNotification: NotificationHandler? = nil,
        onStateChanged: StateHandler? = nil
    ) {
        self.onNotification = onNotification
        self.onStateChanged = onStateChanged
    }

    func connect(to device: YeelightDevice) {
        disconnect(notify: false)

        let sessionGeneration = UUID()
        generation = sessionGeneration
        let endpointPort = NWEndpoint.Port(rawValue: device.port) ?? 55443
        let newConnection = NWConnection(host: NWEndpoint.Host(device.host), port: endpointPort, using: .tcp)
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleState(state, generation: sessionGeneration)
            }
        }

        receive(on: newConnection, generation: sessionGeneration)
        newConnection.start(queue: DispatchQueue(label: "io.github.bekircem.yeelightbar.connection.\(sessionGeneration.uuidString)"))
    }

    func disconnect() {
        disconnect(notify: false)
    }

    func nextCommandID() -> Int {
        commandID += 1
        return commandID
    }

    func send(_ command: YeelightCommand, timeout: TimeInterval = 5) async throws -> YeelightIncomingMessage {
        let data = try command.framedData()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard let connection else {
                    continuation.resume(throwing: YeelightProtocolError.connectionNotReady)
                    return
                }

                pending[command.id] = PendingCommand(
                    completion: { result in
                        continuation.resume(with: result)
                    },
                    timeoutTask: nil
                )

                let nanoseconds = UInt64(timeout.clamped(to: 0.1...60) * 1_000_000_000)
                pending[command.id]?.timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        await self?.resolvePending(id: command.id, result: .failure(YeelightProtocolError.timedOut))
                    } catch {
                        // The response arrived or the command was cancelled.
                    }
                }

                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    guard let error else {
                        return
                    }
                    Task {
                        await self?.resolvePending(id: command.id, result: .failure(error))
                    }
                })
            }
        } onCancel: {
            Task { [weak self] in
                await self?.resolvePending(id: command.id, result: .failure(CancellationError()))
            }
        }
    }

#if DEBUG
    func pendingCommandCount() -> Int {
        pending.count
    }
#endif

    private func receive(on connection: NWConnection, generation sessionGeneration: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            Task {
                await self?.handleReceive(
                    data: data,
                    isComplete: isComplete,
                    error: error,
                    connection: connection,
                    generation: sessionGeneration
                )
            }
        }
    }

    private func handleReceive(
        data: Data?,
        isComplete: Bool,
        error: NWError?,
        connection receivedConnection: NWConnection?,
        generation sessionGeneration: UUID
    ) async {
        guard generation == sessionGeneration, connection === receivedConnection else {
            return
        }

        if let data, !data.isEmpty {
            receiveBuffer.append(data)
            guard processBuffer() else {
                return
            }
        }

        if let error {
            failConnection(error, notifyAs: .failed(error))
            return
        }

        if isComplete {
            failConnection(YeelightProtocolError.disconnected, notifyAs: .cancelled)
            return
        }

        if let receivedConnection {
            receive(on: receivedConnection, generation: sessionGeneration)
        }
    }

    @discardableResult
    private func processBuffer() -> Bool {
        let delimiter = Data([0x0D, 0x0A])

        while let range = receiveBuffer.range(of: delimiter) {
            let line = receiveBuffer[..<range.lowerBound]
            receiveBuffer.removeSubrange(..<range.upperBound)

            guard line.count <= Self.maximumLogicalFrameSize else {
                failConnection(
                    YeelightProtocolError.logicalFrameTooLarge(limit: Self.maximumLogicalFrameSize),
                    notifyAs: .cancelled
                )
                return false
            }

            guard !line.isEmpty else {
                continue
            }

            do {
                let message = try YeelightMessageDecoder.decode(lineData: Data(line))
                switch message {
                case .result(let id, _):
                    resolvePending(id: id, result: .success(message))
                case .failure(let id, _):
                    if let id {
                        resolvePending(id: id, result: .success(message))
                    }
                case .notification(let properties):
                    if let onNotification {
                        Task { @MainActor in
                            onNotification(properties)
                        }
                    }
                }
            } catch {
                failConnection(error, notifyAs: .cancelled)
                return false
            }
        }

        guard receiveBuffer.count <= Self.maximumLogicalFrameSize else {
            failConnection(
                YeelightProtocolError.logicalFrameTooLarge(limit: Self.maximumLogicalFrameSize),
                notifyAs: .cancelled
            )
            return false
        }

        return true
    }

    private func handleState(_ state: NWConnection.State, generation sessionGeneration: UUID) {
        guard generation == sessionGeneration else {
            return
        }

        if let onStateChanged {
            Task { @MainActor in
                onStateChanged(state)
            }
        }

        if case .failed(let error) = state {
            failPending(error)
        }
    }

    private func resolvePending(id: Int, result: Result<YeelightIncomingMessage, Error>) {
        guard let pendingCommand = pending.removeValue(forKey: id) else {
            return
        }

        pendingCommand.timeoutTask?.cancel()
        pendingCommand.completion(result)
    }

    private func failPending(_ error: Error) {
        let pendingCommands = pending.values
        pending.removeAll()
        for pendingCommand in pendingCommands {
            pendingCommand.timeoutTask?.cancel()
            pendingCommand.completion(.failure(error))
        }
    }

    private func failConnection(_ error: Error, notifyAs state: NWConnection.State) {
        let oldConnection = connection
        connection = nil
        generation = UUID()
        receiveBuffer.removeAll(keepingCapacity: false)
        oldConnection?.cancel()
        failPending(error)

        if let onStateChanged {
            Task { @MainActor in
                onStateChanged(state)
            }
        }
    }

    private func disconnect(notify: Bool) {
        let oldConnection = connection
        connection = nil
        generation = UUID()
        oldConnection?.cancel()
        failPending(YeelightProtocolError.disconnected)
        receiveBuffer.removeAll(keepingCapacity: false)

        if notify, let onStateChanged {
            Task { @MainActor in
                onStateChanged(.cancelled)
            }
        }
    }
}
