import Foundation

/// Implements the cmuxd-remote WebSocket relay protocol.
///
/// The daemon speaks a JSON-RPC variant over WebSocket:
///   - Terminal data is base64-encoded in JSON messages
///   - `write` sends user input to the daemon
///   - `session.*` manages terminal sessions
///   - Incoming data arrives as JSON with `data_base64` fields
///
/// Protocol reference: reverse-engineered from cmuxd-remote v0.63.2
@MainActor
final class CmuxdRelayClient {
    let host: String
    let port: Int
    let token: String?

    private var wsTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var nextId: Int = 1
    /// Pending RPC calls keyed by request id.
    private var pendingResponses: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    weak var delegate: CmuxdRelayDelegate?

    private(set) var isConnected = false
    private(set) var sessionId: String?

    init(host: String, port: Int, token: String? = nil) {
        self.host = host
        self.port = port
        self.token = token
    }

    // MARK: - Connection

    func connect() async throws {
        let url: URL
        if token != nil {
            guard let u = URL(string: "wss://\(host):\(port)/") else {
                throw RelayError.invalidURL
            }
            url = u
        } else {
            guard let u = URL(string: "ws://\(host):\(port)/") else {
                throw RelayError.invalidURL
            }
            url = u
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.setValue("cmux-ios/0.1.0", forHTTPHeaderField: "User-Agent")

        let wsTask = session!.webSocketTask(with: request)
        wsTask.resume()
        self.wsTask = wsTask
        isConnected = true
        delegate?.relayDidConnect()

        // If we have a token, authenticate
        if let token = token {
            try await authenticate(token: token)
        }

        // Start the receive loop
        await receiveLoop()
    }

    func disconnect() {
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        // Cancel all pending RPC calls
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: RelayError.notConnected)
        }
        pendingResponses.removeAll()
    }

    // MARK: - Session Management

    /// Create a basic terminal session on the daemon.
    func createSession(cols: Int = 80, rows: Int = 24) async throws -> String {
        let params: [String: JSONValue] = [
            "cols": .number(Double(cols)),
            "rows": .number(Double(rows))
        ]
        let response = try await call(method: "session.basic", params: .object(params))
        // Response should contain session_id
        if case .object(let dict) = response, let sid = dict["session_id"]?.stringValue {
            sessionId = sid
            return sid
        }
        throw RelayError.missingSessionID
    }

    /// Resize the terminal session (must match PTY dimensions).
    func resizeSession(cols: Int, rows: Int) async throws {
        guard let sid = sessionId else { throw RelayError.notConnected }
        let params: [String: JSONValue] = [
            "session_id": .string(sid),
            "cols": .number(Double(cols)),
            "rows": .number(Double(rows))
        ]
        _ = try await call(method: "session.resize", params: .object(params))
    }

    /// Close the terminal session on the daemon.
    func closeSession() async throws {
        guard let sid = sessionId else { return }
        let params: [String: JSONValue] = ["session_id": .string(sid)]
        _ = try await call(method: "session.close", params: .object(params))
        sessionId = nil
    }

    /// Send terminal input (user keystrokes) to the daemon.
    func sendInput(_ text: String) {
        guard isConnected else { return }
        guard let data = text.data(using: .utf8) else { return }
        let b64 = data.base64EncodedString()

        let payload: [String: JSONValue] = [
            "method": .string("write"),
            "params": .object(["data_base64": .string(b64)])
        ]
        if let json = try? encoder.encode(payload) {
            wsTask?.send(.data(json)) { _ in }
        }
    }

    // MARK: - Private

    private func authenticate(token: String) async throws {
        let params: [String: JSONValue] = ["token": .string(token)]
        _ = try await call(method: "relay.auth", params: .object(params))
    }

    /// Perform a JSON-RPC call and return the result.
    private func call(method: String, params: JSONValue) async throws -> JSONValue {
        try ensureConnected()

        let id = nextId
        nextId += 1

        let request: [String: JSONValue] = [
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ]

        let jsonData = try encoder.encode(request)
        try await wsTask?.send(.data(jsonData))

        // Wait for response with matching id
        return try await waitForResponse(id: id)
    }

    private func ensureConnected() throws {
        guard isConnected, wsTask != nil else {
            throw RelayError.notConnected
        }
    }

    /// Receive loop: process all incoming WebSocket messages.
    private func receiveLoop() async {
        while isConnected, let wsTask = wsTask {
            do {
                let message = try await wsTask.receive()
                switch message {
                case .data(let data):
                    handleMessage(data: data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        handleMessage(data: data)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    isConnected = false
                    delegate?.relayDidDisconnect(error: error)
                }
                break
            }
        }
    }

    /// Handle incoming JSON message from the daemon.
    private func handleMessage(data: Data) {
        guard let json = try? decoder.decode(JSONMessage.self, from: data) else {
            return
        }

        // Check for terminal output (no id means unsolicited data)
        if json.id == nil {
            if let method = json.method {
                switch method {
                case "data":
                    if let b64 = json.paramsData?["data_base64"]?.stringValue,
                       let decoded = Data(base64Encoded: b64) {
                        delegate?.relayDidReceiveOutput(decoded)
                    }
                default:
                    break
                }
            }
            return
        }

        // RPC response — resolve pending continuation
        if let id = json.id, let continuation = pendingResponses.removeValue(forKey: id) {
            if let result = json.result {
                continuation.resume(returning: result)
            } else if let error = json.error {
                continuation.resume(throwing: RelayError.rpcError("\(error)"))
            } else {
                // Unstructured response with id but no result/error — treat as null
                continuation.resume(returning: .null)
            }
        }
    }

    /// Wait for a response with a matching id (for RPC calls).
    private func waitForResponse(id: Int) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
        }
    }

    deinit {
        wsTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: RelayError.notConnected)
        }
    }
}

// MARK: - Types

enum RelayError: LocalizedError {
    case invalidURL
    case notConnected
    case missingSessionID
    case authenticationFailed
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid relay URL"
        case .notConnected: return "Not connected to relay"
        case .missingSessionID: return "No session ID from daemon"
        case .authenticationFailed: return "Relay authentication failed"
        case .rpcError(let msg): return "RPC error: \(msg)"
        }
    }
}

/// Cmuxd relay events.
@MainActor
protocol CmuxdRelayDelegate: AnyObject {
    func relayDidConnect()
    func relayDidDisconnect(error: Error?)
    func relayDidReceiveOutput(_ data: Data)
}

// MARK: - JSON Helpers

/// Minimal JSON value for building RPC payloads without dependencies.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .object(let d): try container.encode(d)
        case .array(let a): try container.encode(a)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let d = try? container.decode([String: JSONValue].self) { self = .object(d); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: container.codingPath,
                                  debugDescription: "Unknown JSON value"))
    }
}

/// Structured JSON message from the relay.
private struct JSONMessage: Codable {
    let id: Int?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONValue?

    /// Flatten params into a dict for easy access.
    var paramsData: [String: JSONValue]? {
        if case .object(let d) = params { return d }
        return nil
    }
}
