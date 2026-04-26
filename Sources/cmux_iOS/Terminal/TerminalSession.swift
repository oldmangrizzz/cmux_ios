import Foundation
import SwiftTerm
@preconcurrency import Citadel
import NIOCore

/// Represents the transport layer for a terminal session.
/// On iOS we can't fork/exec, so sessions connect to remote hosts.
enum SessionTransport: Codable, Equatable, Identifiable, Sendable {
    /// Direct connection to cmuxd-remote via WebSocket relay.
    case cmuxdRelay(host: String, port: Int, token: String?)
    /// SSH connection using Citadel (SwiftNIO SSH).
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

/// Actor wrapper around the SSH outbound writer so `sendInput` and `resize`
/// can be called from `@MainActor` without capturing `self` in the
/// `withTTY` closure (which would make it non-Sendable under Swift 6).
actor SSHIOBridge {
    private var outbound: TTYStdinWriter?

    func setOutbound(_ writer: TTYStdinWriter) {
        self.outbound = writer
    }

    func clearOutbound() {
        self.outbound = nil
    }

    func send(_ text: String) async {
        guard let outbound else { return }
        let buffer = ByteBuffer(string: text)
        try? await outbound.write(buffer)
    }

    func resize(cols: Int, rows: Int) async {
        guard let outbound else { return }
        try? await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }
}

/// Actor box to ferry an error out of a nonisolated closure.
actor ErrorBox {
    private(set) var error: Error?
    func set(_ e: Error?) { error = e }
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
///   - `.ssh`: SSH connection via Citadel (SwiftNIO SSH)
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
    private var wsTask: URLSessionWebSocketTask?
    private var sshClient: SSHClient?
    private var sshBridge: SSHIOBridge?

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
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        sshBridge = nil
        sshClient = nil
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
        } else if let bridge = sshBridge {
            Task {
                try? await bridge.send(text)
            }
        }
    }

    /// Resize the remote PTY.
    func resize(cols: Int, rows: Int) {
        guard isConnected else { return }
        Task { [weak self] in
            try? await self?.relayClient?.resizeSession(cols: cols, rows: rows)
            try? await self?.sshBridge?.resize(cols: cols, rows: rows)
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

    /// SSH via Citadel (SwiftNIO SSH).
    private func connectSSH(host: String, port: Int, user: String, auth: SSHAuth) async throws {
        let authMethod: SSHAuthenticationMethod
        switch auth {
        case .password(let password):
            authMethod = SSHAuthenticationMethod.passwordBased(username: user, password: password)
        case .key:
            throw TerminalError.notImplemented("SSH key authentication requires a key store. Use password auth or a relay.")
        }

        let client = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )
        self.sshClient = client

        let bridge = SSHIOBridge()
        self.sshBridge = bridge

        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()
        let errorBox = ErrorBox()

        let outputTask = Task { @MainActor [weak self] in
            for await data in outputStream {
                self?.receiveOutput(data)
            }
        }

        self.isConnected = true
        self.title = "ssh:\(user)@\(host)"
        self.delegate?.sessionDidConnect()

        do {
            try await Self.runTTYSession(
                client: client,
                bridge: bridge,
                continuation: outputContinuation,
                errorBox: errorBox
            )

            await outputTask.value
            self.isConnected = false
            self.sshBridge = nil
            self.sshClient = nil
            self.delegate?.sessionDidDisconnect(error: await errorBox.error)
        } catch {
            outputContinuation.finish()
            await outputTask.value
            self.isConnected = false
            self.sshBridge = nil
            self.sshClient = nil
            throw error
        }
    }

    /// Nonisolated helper so the `withTTY` closure does not capture
    /// `@MainActor`-isolated `self` (which would make the closure non-Sendable).
    nonisolated private static func runTTYSession(
        client: SSHClient,
        bridge: SSHIOBridge,
        continuation: AsyncStream<Data>.Continuation,
        errorBox: ErrorBox
    ) async throws {
        try await client.withTTY { (inbound: TTYOutput, outbound: TTYStdinWriter) in
            await bridge.setOutbound(outbound)
            defer { Task { await bridge.clearOutbound() } }

            do {
                for try await output in inbound {
                    switch output {
                    case .stdout(let buffer), .stderr(let buffer):
                        if let data = buffer.getData(at: 0, length: buffer.readableBytes) {
                            continuation.yield(data)
                        }
                    }
                }
            } catch {
                await errorBox.set(error)
            }
            continuation.finish()
        }
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
        wsTask?.cancel()
        relayClient = nil
        task?.cancel()
    }
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
