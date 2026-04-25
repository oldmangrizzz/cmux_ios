import Foundation
import SwiftTerm

/// Represents the transport layer for a terminal session.
/// On iOS we can't fork/exec, so sessions connect to remote hosts.
enum SessionTransport: Codable, Equatable, Identifiable, Sendable {
    /// Direct connection to cmuxd-remote via WebSocket relay.
    case cmuxdRelay(host: String, port: Int, token: String?)
    /// SSH connection (forwarded through a WebSocket relay proxy).
    case ssh(host: String, port: Int, user: String, auth: SSHAuth)
    /// Generic WebSocket terminal server (e.g., a tmux relay).
    case webSocket(url: String)
    /// Loopback to a local relay for testing.
    case local(String)

    var id: String {
        switch self {
        case .cmuxdRelay(let h, let p, _): return "cmuxd:\(h):\(p)"
        case .ssh(let h, let p, let u, _): return "ssh:\(u)@\(h):\(p)"
        case .webSocket(let u): return "ws:\(u)"
        case .local(let n): return "local:\(n)"
        }
    }

    var label: String {
        switch self {
        case .cmuxdRelay(_, _, _): return "cmuxd Relay"
        case .ssh(_, _, let u, _): return u
        case .webSocket: return "WebSocket"
        case .local: return "Local"
        }
    }
}

enum SSHAuth: Codable, Equatable, Sendable {
    case password(String)
    case key(id: String, passphrase: String?)
}

/// Observes terminal I/O events from a session.
@MainActor
protocol TerminalSessionDelegate: AnyObject {
    func sessionDidReceiveOutput(_ data: Data)
    func sessionDidDisconnect(error: Error?)
    func sessionDidConnect()
}

/// Manages a terminal connection — feeds output to the terminal,
/// sends input from the user.
///
/// Transport options:
///   - `.cmuxdRelay`: connects to cmuxd-remote's WebSocket relay directly
///   - `.webSocket`: generic WebSocket terminal server
///   - `.ssh`: SSH connection (requires SSH library, falls back to relay)
///   - `.local`: local relay (test harness or cmuxd socket proxy)
@MainActor
final class TerminalSession: Identifiable, ObservableObject {
    let id = UUID()
    let transport: SessionTransport

    @Published var title: String
    @Published var isConnected = false

    weak var delegate: TerminalSessionDelegate?

    private var task: Task<Void, Never>?
    private var relayClient: CmuxdRelayClient?

    init(transport: SessionTransport, title: String? = nil) {
        self.transport = transport
        self.title = title ?? transport.label
    }

    // MARK: - Lifecycle

    func connect() {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch self.transport {
                case .cmuxdRelay(let host, let port, let token):
                    try await self.connectRelay(host: host, port: port, token: token)
                case .ssh(let host, let port, let user, let auth):
                    try await self.connectSSH(host: host, port: port, user: user, auth: auth)
                case .webSocket(let url):
                    try await self.connectWebSocket(url: url)
                case .local:
                    try await self.connectLocal()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.delegate?.sessionDidDisconnect(error: error)
                    }
                }
            }
        }
    }

    func disconnect() {
        relayClient?.disconnect()
        relayClient = nil
        (wsTask as? URLSessionWebSocketTask)?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        task?.cancel()
        task = nil
        isConnected = false
    }

    /// Send user keystrokes / input to the remote.
    func sendInput(_ text: String) {
        guard isConnected else { return }
        if let client = relayClient {
            client.sendInput(text)
        } else if let wsTask = wsTask {
            guard let data = text.data(using: .utf8) else { return }
            wsTask.send(.data(data)) { _ in }
        }
    }

    /// Resize the remote PTY.
    func resize(cols: Int, rows: Int) {
        guard isConnected else { return }
        Task {
            try? await relayClient?.resizeSession(cols: cols, rows: rows)
        }
    }

    /// Feed received bytes into the terminal.
    func receiveOutput(_ data: Data) {
        delegate?.sessionDidReceiveOutput(data)
    }

    // MARK: - Transport Implementations

    /// Connect to cmuxd-remote WebSocket relay.
    private func connectRelay(host: String, port: Int, token: String?) async throws {
        let client = CmuxdRelayClient(host: host, port: port, token: token)
        self.relayClient = client
        client.delegate = RelayDelegateBridge(session: self)

        try await client.connect()

        _ = try await client.createSession(cols: 80, rows: 24)
        isConnected = true
        title = "cmuxd@\(host)"
        delegate?.sessionDidConnect()
    }

    /// SSH via relay proxy — connects through cmuxd's proxy.stream.
    private func connectSSH(host: String, port: Int, user: String, auth: SSHAuth) async throws {
        throw TerminalError.notImplemented(
            "Direct SSH requires libssh2. Use cmuxdRelay transport or a WebSocket proxy."
        )
    }

    /// Generic WebSocket terminal server.
    private func connectWebSocket(url: String) async throws {
        guard let wsURL = URL(string: url) else { throw TerminalError.invalidURL }
        let urlSession = URLSession(configuration: .default)
        let wsTask = urlSession.webSocketTask(with: wsURL)
        wsTask.resume()
        self.wsTask = wsTask

        isConnected = true
        delegate?.sessionDidConnect()

        // Receive loop
        while !Task.isCancelled {
            do {
                let message = try await wsTask.receive()
                switch message {
                case .data(let data):
                    self.receiveOutput(data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self.receiveOutput(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    delegate?.sessionDidDisconnect(error: error)
                }
                break
            }
        }
    }

    /// Local loopback (test harness or cmuxd Unix socket).
    private func connectLocal() async throws {
        throw TerminalError.notImplemented("Local requires a relay daemon or cmuxd socket proxy")
    }

    deinit {
        (wsTask as? URLSessionWebSocketTask)?.cancel()
        relayClient = nil
        task?.cancel()
    }

    // MARK: - Internal state for WebSocket transport

    private var wsTask: URLSessionWebSocketTask?
}

// MARK: - Relay Delegate Bridge

/// Bridges CmuxdRelayDelegate to TerminalSessionDelegate.
@MainActor
private final class RelayDelegateBridge: CmuxdRelayDelegate {
    weak var session: TerminalSession?

    init(session: TerminalSession) {
        self.session = session
    }

    nonisolated func relayDidConnect() {
        Task { @MainActor [weak self] in
            self?.session?.isConnected = true
            self?.session?.delegate?.sessionDidConnect()
        }
    }

    nonisolated func relayDidDisconnect(error: Error?) {
        Task { @MainActor [weak self] in
            self?.session?.isConnected = false
            self?.session?.delegate?.sessionDidDisconnect(error: error)
        }
    }

    nonisolated func relayDidReceiveOutput(_ data: Data) {
        Task { @MainActor [weak self] in
            self?.session?.receiveOutput(data)
        }
    }
}

// MARK: - Errors

enum TerminalError: LocalizedError {
    case notImplemented(String)
    case invalidURL
    case relayError(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let feature): return "Not implemented: \(feature)"
        case .invalidURL: return "Invalid WebSocket URL"
        case .relayError(let msg): return "Relay error: \(msg)"
        }
    }
}
