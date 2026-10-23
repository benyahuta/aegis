// `remote_access_off` probes (SPEC §6.2): an NWConnection TCP connect to 127.0.0.1 on ports 22,
// 5900, 445 and 548, each with a 300 ms timeout. Loopback only; nothing is sent or read; every
// connection is cancelled as soon as its state is known.
// macOS only (the iPhone app never probes ports).

#if os(macOS)
import Foundation
import Network
import os

public struct LoopbackProber: LoopbackProbing {
    /// §6.2: 300 ms per port.
    public static let perPortTimeout: TimeInterval = 0.3

    public init() {}

    /// Probes the four fixed §6.2 ports concurrently.
    public func probeRemoteAccessPorts() async -> [UInt16: PortProbeResult] {
        await withTaskGroup(of: (UInt16, PortProbeResult).self) { group in
            for port in MacDerivedParsers.remoteAccessPorts {
                group.addTask { (port, await Self.probe(port: port, timeout: Self.perPortTimeout)) }
            }
            var results: [UInt16: PortProbeResult] = [:]
            for await (port, result) in group { results[port] = result }
            return results
        }
    }

    /// Internal so tests can probe a port they control. The host is always 127.0.0.1.
    static func probe(port: UInt16, timeout: TimeInterval) async -> PortProbeResult {
        guard let endpointPort = NWEndpoint.Port(rawValue: port), port != 0 else { return .indeterminate }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: parameters)
        let queue = DispatchQueue(label: AppIdentity.prefix + ".loopback-probe")

        return await withCheckedContinuation { continuation in
            let gate = ProbeGate(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(.open)
                case .waiting(let error), .failed(let error):
                    gate.finish(Self.isRefused(error) ? .closed : .indeterminate)
                case .cancelled:
                    gate.finish(.indeterminate)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { gate.finish(.indeterminate) }
        }
    }

    static func isRefused(_ error: NWError) -> Bool {
        if case .posix(let code) = error { return code == .ECONNREFUSED }
        return false
    }
}

/// Resumes the continuation exactly once and cancels the connection.
private final class ProbeGate: Sendable {
    private let connection: NWConnection
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<PortProbeResult, Never>?>

    init(connection: NWConnection, continuation: CheckedContinuation<PortProbeResult, Never>) {
        self.connection = connection
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func finish(_ result: PortProbeResult) {
        let pending = continuation.withLock { value -> CheckedContinuation<PortProbeResult, Never>? in
            defer { value = nil }
            return value
        }
        guard let pending else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        pending.resume(returning: result)
    }
}
#endif
