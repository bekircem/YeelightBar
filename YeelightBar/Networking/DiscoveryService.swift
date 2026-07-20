import Foundation
import Network

actor DiscoveryService {
    typealias DeviceHandler = @MainActor @Sendable (YeelightDevice, String) -> Void
    typealias ErrorHandler = @MainActor @Sendable (Error) -> Void
    typealias RejectionHandler = @MainActor @Sendable (String) -> Void

    private var group: NWConnectionGroup?
    private let onDeviceFound: DeviceHandler?
    private let onError: ErrorHandler?
    private let onRejectedPacket: RejectionHandler?

    init(
        onDeviceFound: DeviceHandler? = nil,
        onError: ErrorHandler? = nil,
        onRejectedPacket: RejectionHandler? = nil
    ) {
        self.onDeviceFound = onDeviceFound
        self.onError = onError
        self.onRejectedPacket = onRejectedPacket
    }

    func start() {
        guard group == nil else {
            return
        }

        do {
            let multicast = try NWMulticastGroup(for: [
                .hostPort(host: "239.255.255.250", port: 1982)
            ])
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true

            let newGroup = NWConnectionGroup(with: multicast, using: parameters)
            group = newGroup

            newGroup.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleState(state)
                }
            }

            configureReceiveHandler(on: newGroup)
            newGroup.start(queue: DispatchQueue(label: "io.github.bekircem.yeelightbar.discovery"))
        } catch {
            report(error)
        }
    }

    func search() {
        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1982\r
        MAN: "ssdp:discover"\r
        ST: wifi_bulb\r
        \r

        """

        group?.send(content: Data(payload.utf8), to: nil, message: .default) { [weak self] error in
            guard let error else { return }
            Task {
                await self?.report(error)
            }
        }
    }

    func stop() {
        group?.cancel()
        group = nil
    }

    private func configureReceiveHandler(on group: NWConnectionGroup) {
        group.setReceiveHandler(maximumMessageSize: 16 * 1024, rejectOversizedMessages: true) { [weak self] context, content, _ in
            Task {
                await self?.handlePacket(context: context, content: content)
            }
        }
    }

    private func handlePacket(context: NWConnectionGroup.Message, content: Data?) {
        guard let sourceHost = Self.sourceHost(from: context.remoteEndpoint) else {
            reject("Discovery packet without an IP source")
            return
        }

        guard let content, let message = String(data: content, encoding: .utf8) else {
            reject("Discovery packet is not valid UTF-8")
            return
        }

        do {
            let device = try DiscoveryResponseParser.parse(message, sourceHost: sourceHost)
            if let onDeviceFound {
                Task { @MainActor in
                    onDeviceFound(device, sourceHost)
                }
            }
        } catch {
            reject(error.localizedDescription)
        }
    }

    private func handleState(_ state: NWConnectionGroup.State) {
        if case .failed(let error) = state {
            report(error)
        }
    }

    private func report(_ error: Error) {
        if let onError {
            Task { @MainActor in
                onError(error)
            }
        }
    }

    private func reject(_ reason: String) {
        if let onRejectedPacket {
            Task { @MainActor in
                onRejectedPacket(reason)
            }
        }
    }

    private static func sourceHost(from endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, _) = endpoint else {
            return nil
        }

        switch host {
        case .ipv4(let address):
            return address.debugDescription
        case .ipv6(let address):
            return address.debugDescription
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }
}
