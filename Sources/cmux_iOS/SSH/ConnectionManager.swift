import Foundation

/// Manages saved connections and active terminal sessions.
@MainActor
final class ConnectionManager: ObservableObject {
    @Published var savedConnections: [SessionTransport] = []
    @Published var activeSessions: [TerminalSession] = []

    static let shared = ConnectionManager()

    private let storageKey = "cmux_saved_connections"

    private init() {
        loadConnections()
    }

    // MARK: - Connection Management

    func addConnection(_ transport: SessionTransport) {
        if !savedConnections.contains(transport) {
            savedConnections.append(transport)
            saveConnections()
        }
    }

    func removeConnection(_ transport: SessionTransport) {
        savedConnections.removeAll { $0 == transport }
        saveConnections()
    }

    func newSession(transport: SessionTransport) -> TerminalSession {
        let session = TerminalSession(transport: transport)
        activeSessions.append(session)
        return session
    }

    func closeSession(_ session: TerminalSession) {
        session.disconnect()
        activeSessions.removeAll { $0.id == session.id }
    }

    func closeAllSessions() {
        activeSessions.forEach { $0.disconnect() }
        activeSessions.removeAll()
    }

    // MARK: - Persistence

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(savedConnections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let connections = try? JSONDecoder().decode([SessionTransport].self, from: data)
        else { return }
        savedConnections = connections
    }
}
