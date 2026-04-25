import SwiftUI

/// App settings — theme selection, appearance, about.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTheme: TerminalTheme
    @Binding var showSidebar: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(allThemes, id: \.name) { theme in
                            HStack {
                                Circle()
                                    .fill(theme.backgroundColor)
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(.secondary, lineWidth: 1))
                                Text(theme.name)
                            }
                            .tag(theme)
                        }
                    }

                    Toggle("Show Sidebar", isOn: $showSidebar)
                }

                Section("Terminal") {
                    HStack {
                        Text("Font")
                        Spacer()
                        Text("SF Mono")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Scrollback")
                        Spacer()
                        Text("10,000 lines")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("cmux_iOS")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("A mobile terminal companion inspired by cmux.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
