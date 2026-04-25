import SwiftUI

/// Root view: sidebar + terminal area + tab bar.
struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var connectionManager = ConnectionManager.shared
    @State private var selectedTheme: TerminalTheme = .default
    @State private var showSidebar = true
    @State private var showConnectionSheet = false
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebar
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                TerminalTabBarView(tabManager: tabManager, showSidebar: $showSidebar)

                if let splitVM = tabManager.selectedSplitVM {
                    SplitPaneView(splitVM: splitVM)
                } else {
                    emptyTerminalArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.windowBackground(in: selectedTheme.name == "cmux Dark" ? .dark : .light))
        .preferredColorScheme(selectedTheme.name == "cmux Dark" ? .dark : .light)
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSetupView(connectionManager: connectionManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedTheme: $selectedTheme, showSidebar: $showSidebar)
        }
        .onChange(of: connectionManager.activeSessions.count) { _, newCount in
            if newCount > (tabManager.selectedSplitVM?.panes.count ?? 0) {
                // A new session was created — add it to the current or new tab
                if let session = connectionManager.activeSessions.last {
                    let splitVM = tabManager.selectedSplitVM ?? tabManager.newTab()
                    splitVM.split(
                        viewModel: TerminalViewModel(session: session, theme: selectedTheme),
                        direction: .horizontal
                    )
                    session.connect()
                }
            }
        }
        .onChange(of: selectedTheme) { _, newTheme in
            // Update all running terminal views with the new theme
            for tab in tabManager.tabs {
                for pane in tab.splitVM.panes {
                    pane.viewModel.theme = newTheme
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            List {
                if !connectionManager.activeSessions.isEmpty {
                    Section("Active Sessions") {
                        ForEach(connectionManager.activeSessions) { session in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(session.isConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(session.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    connectionManager.closeSession(session)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !connectionManager.savedConnections.isEmpty {
                    Section("Saved") {
                        ForEach(connectionManager.savedConnections, id: \.id) { transport in
                            Button {
                                let session = connectionManager.newSession(transport: transport)
                                let splitVM = tabManager.selectedSplitVM ?? tabManager.newTab()
                                splitVM.split(
                                    viewModel: TerminalViewModel(session: session, theme: selectedTheme),
                                    direction: .horizontal
                                )
                                session.connect()
                            } label: {
                                Label(transport.label, systemImage: "server.rack")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if connectionManager.activeSessions.isEmpty && connectionManager.savedConnections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "plug")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No connections")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Tap + to add a connection")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            .listStyle(.sidebar)

            bottomBar
        }
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("cmux")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                showConnectionSheet = true
            } label: {
                Label("Connect", systemImage: "plus")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(.separator.opacity(0.1))
    }

    // MARK: - Empty State

    private var emptyTerminalArea: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("cmux for iOS")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Connect to a remote server via SSH or WebSocket\nto start a terminal session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showConnectionSheet = true
            } label: {
                Label("New Connection", systemImage: "plus.circle.fill")
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}

#Preview {
    ContentView()
}
