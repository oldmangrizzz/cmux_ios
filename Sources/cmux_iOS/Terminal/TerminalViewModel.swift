import Foundation
import SwiftTerm
import SwiftUI

/// Bridges a TerminalSession to SwiftUI, owning the terminal view reference.
@MainActor
final class TerminalViewModel: ObservableObject, TerminalSessionDelegate {
    let session: TerminalSession

    @Published var theme: TerminalTheme = .default
    @Published var columns: Int = 80
    @Published var rows: Int = 24
    @Published var title: String = ""
    @Published var isConnected: Bool = false
    @Published var isFullScreen: Bool = false

    /// Reference back to the SwiftTerm.TerminalView for feeding output.
    weak var terminalView: SwiftTerm.TerminalView?

    init(session: TerminalSession, theme: TerminalTheme = .default) {
        self.session = session
        self.theme = theme
        self.title = session.title
        self.isConnected = session.isConnected
        session.delegate = self
    }

    func connect() {
        session.connect()
    }

    func disconnect() {
        session.disconnect()
    }

    /// Send data from the terminal (user keystrokes) to the transport layer.
    func sendInput(_ data: Data) {
        session.sendInput(String(decoding: data, as: UTF8.self))
    }

    /// Called by the transport layer with received bytes — feed to terminal.
    private func feedOutput(_ data: Data) {
        let bytes = [UInt8](data)
        terminalView?.feed(byteArray: bytes[...])
    }

    // MARK: - TerminalSessionDelegate

    nonisolated func sessionDidReceiveOutput(_ data: Data) {
        Task { @MainActor [weak self] in
            self?.feedOutput(data)
        }
    }

    nonisolated func sessionDidDisconnect(error: Error?) {
        Task { @MainActor [weak self] in
            self?.isConnected = false
            // Append disconnect notice to the terminal
            let msg = "\r\n\u{1b}[31m[disconnected]\u{1b}[0m \(error?.localizedDescription ?? "")\r\n"
            if let data = msg.data(using: .utf8) {
                self?.feedOutput(data)
            }
        }
    }

    nonisolated func sessionDidConnect() {
        Task { @MainActor [weak self] in
            self?.isConnected = true
        }
    }
}
