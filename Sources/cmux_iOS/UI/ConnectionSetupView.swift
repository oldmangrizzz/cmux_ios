import SwiftUI

/// View for configuring and saving terminal connections.
/// Supports SSH, WebSocket, and cmuxd Relay transport types.
struct ConnectionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var connectionManager: ConnectionManager

    // Common fields
    @State private var connectionName = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var transportType: TransportType = .ssh

    // SSH fields
    @State private var user = "root"
    @State private var authMethod: AuthMethod = .password
    @State private var password = ""
    @State private var identityFile = ""

    // cmuxd Relay fields
    @State private var relayToken = ""

    enum TransportType: String, CaseIterable {
        case ssh = "SSH"
        case webSocket = "WebSocket"
        case cmuxdRelay = "cmuxd Relay"
    }

    enum AuthMethod: String, CaseIterable {
        case password = "Password"
        case key = "Key"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name (optional)", text: $connectionName)
                        .autocorrectionDisabled()

                    Picker("Type", selection: $transportType) {
                        ForEach(TransportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)

                    if transportType == .ssh {
                        TextField("User", text: $user)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                    }

                    if transportType == .cmuxdRelay {
                        SecureField("Auth Token (optional)", text: $relayToken)
                    }
                }

                if transportType == .ssh {
                    Section("Authentication") {
                        Picker("Method", selection: $authMethod) {
                            ForEach(AuthMethod.allCases, id: \.self) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }

                        if authMethod == .password {
                            SecureField("Password", text: $password)
                        } else {
                            TextField("Identity file path", text: $identityFile)
                                .autocorrectionDisabled()
                        }
                    }
                }

                Section {
                    Button("Connect") {
                        saveAndConnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty)
                }

                if !connectionManager.savedConnections.isEmpty {
                    Section("Saved Connections") {
                        ForEach(connectionManager.savedConnections, id: \.id) { transport in
                            Button {
                                connectSaved(transport)
                            } label: {
                                HStack {
                                    Image(systemName: icon(for: transport))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(transport.label)
                                            .font(.body)
                                        Text(transport.id)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                connectionManager.removeConnection(connectionManager.savedConnections[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func icon(for transport: SessionTransport) -> String {
        switch transport {
        case .ssh: return "terminal"
        case .webSocket: return "antenna.radiowaves.left.and.right"
        case .cmuxdRelay: return "arrow.triangle.branch"
        case .local: return "laptopcomputer"
        }
    }

    private func saveAndConnect() {
        let transport: SessionTransport

        switch transportType {
        case .ssh:
            let auth = SSHAuth.password(password)
            transport = .ssh(
                host: host,
                port: Int(port) ?? 22,
                user: user,
                auth: auth
            )
        case .webSocket:
            let url = host.hasPrefix("ws") ? host : "ws://\(host):\(port)"
            transport = .webSocket(url: url)
        case .cmuxdRelay:
            let token = relayToken.isEmpty ? nil : relayToken
            transport = .cmuxdRelay(
                host: host,
                port: Int(port) ?? 9123,
                token: token
            )
        }

        connectionManager.addConnection(transport)
        _ = connectionManager.newSession(transport: transport)
        dismiss()
    }

    private func connectSaved(_ transport: SessionTransport) {
        _ = connectionManager.newSession(transport: transport)
        dismiss()
    }
}
