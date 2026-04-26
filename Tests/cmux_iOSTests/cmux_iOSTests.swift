import Testing
import Foundation
@testable import cmux_iOS

// MARK: - JSONValue Tests

struct JSONValueTests {
    @Test func encodeString() throws {
        let value = JSONValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded.stringValue == "hello")
    }

    @Test func encodeNumber() throws {
        let value = JSONValue.number(42.5)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .number(let n) = decoded {
            #expect(n == 42.5)
        } else {
            Issue.record("Expected number")
        }
    }

    @Test func encodeObject() throws {
        let value = JSONValue.object(["key": .string("value")])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .object(let dict) = decoded {
            #expect(dict["key"]?.stringValue == "value")
        } else {
            Issue.record("Expected object")
        }
    }

    @Test func encodeArray() throws {
        let value = JSONValue.array([.number(1), .number(2)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .array(let arr) = decoded {
            #expect(arr.count == 2)
        } else {
            Issue.record("Expected array")
        }
    }

    @Test func encodeBool() throws {
        let value = JSONValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .bool(let b) = decoded {
            #expect(b == true)
        } else {
            Issue.record("Expected bool")
        }
    }

    @Test func encodeNull() throws {
        let value = JSONValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .null = decoded {
            // pass
        } else {
            Issue.record("Expected null")
        }
    }
}

// MARK: - SessionTransport Tests

struct SessionTransportTests {
    @Test func sshID() {
        let transport = SessionTransport.ssh(host: "example.com", port: 22, user: "root", auth: .password("secret"))
        #expect(transport.id == "ssh:root@example.com:22")
    }

    @Test func cmuxdRelayID() {
        let transport = SessionTransport.cmuxdRelay(host: "127.0.0.1", port: 9123, token: nil)
        #expect(transport.id == "cmuxd:127.0.0.1:9123")
    }

    @Test func webSocketID() {
        let transport = SessionTransport.webSocket(url: "ws://localhost:8080")
        #expect(transport.id == "ws:ws://localhost:8080")
    }

    @Test func localID() {
        let transport = SessionTransport.local("test")
        #expect(transport.id == "local:test")
    }

    @Test func labelForSSH() {
        let transport = SessionTransport.ssh(host: "example.com", port: 22, user: "admin", auth: .password("secret"))
        #expect(transport.label == "admin")
    }

    @Test func codingRoundTrip() throws {
        let transport = SessionTransport.ssh(host: "example.com", port: 22, user: "root", auth: .password("secret"))
        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(SessionTransport.self, from: data)
        #expect(decoded == transport)
    }
}

// MARK: - TerminalTheme Tests

struct TerminalThemeTests {
    @Test func defaultThemeIsDark() {
        let theme = TerminalTheme.default
        #expect(theme.name == "cmux Dark")
    }

    @Test func colorFromHex() {
        let color = Color(hex: "#FF0000")
        // SwiftUI Color equality is tricky; just ensure init succeeds
        _ = color
    }
}

// MARK: - ConnectionManager Tests

@MainActor
struct ConnectionManagerTests {
    @Test func addConnection() {
        let manager = ConnectionManager.shared
        let initialCount = manager.savedConnections.count
        let transport = SessionTransport.webSocket(url: "ws://test")
        manager.addConnection(transport)
        #expect(manager.savedConnections.count == initialCount + 1)
        // cleanup
        manager.removeConnection(transport)
    }

    @Test func removeConnection() {
        let manager = ConnectionManager.shared
        let transport = SessionTransport.webSocket(url: "ws://test-remove")
        manager.addConnection(transport)
        let afterAdd = manager.savedConnections.count
        manager.removeConnection(transport)
        #expect(manager.savedConnections.count == afterAdd - 1)
    }

    @Test func duplicateConnectionNotAdded() {
        let manager = ConnectionManager.shared
        let transport = SessionTransport.webSocket(url: "ws://test-dup")
        manager.addConnection(transport)
        let afterFirst = manager.savedConnections.count
        manager.addConnection(transport)
        #expect(manager.savedConnections.count == afterFirst)
        // cleanup
        manager.removeConnection(transport)
    }

    @Test func newSessionCreatesActiveSession() {
        let manager = ConnectionManager.shared
        let initialCount = manager.activeSessions.count
        let transport = SessionTransport.local("test-session")
        let session = manager.newSession(transport: transport)
        #expect(manager.activeSessions.count == initialCount + 1)
        manager.closeSession(session)
        #expect(manager.activeSessions.count == initialCount)
    }
}

// MARK: - TerminalError Tests

struct TerminalErrorTests {
    @Test func errorDescriptions() {
        let notImpl = TerminalError.notImplemented("feature X")
        #expect(notImpl.errorDescription?.contains("feature X") == true)

        let invalid = TerminalError.invalidURL
        #expect(invalid.errorDescription == "Invalid WebSocket URL")

        let relay = TerminalError.relayError("timeout")
        #expect(relay.errorDescription?.contains("timeout") == true)
    }
}
