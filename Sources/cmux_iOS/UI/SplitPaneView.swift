import SwiftUI

enum SplitDirection: Equatable {
    case horizontal
    case vertical
}

/// Manages a split pane layout within a tab.
@MainActor
final class SplitPaneViewModel: ObservableObject {
    @Published var direction: SplitDirection = .horizontal
    @Published var panes: [Pane] = []

    struct Pane: Identifiable {
        let id = UUID()
        let viewModel: TerminalViewModel
    }

    var activePane: Pane? { panes.last }

    func split(viewModel: TerminalViewModel, direction: SplitDirection) {
        self.direction = direction
        panes.append(Pane(viewModel: viewModel))
    }

    func closePane(id: UUID) {
        panes.removeAll { $0.id == id }
    }
}

/// Renders split panes containing terminal views.
struct SplitPaneView: View {
    @ObservedObject var splitVM: SplitPaneViewModel

    var body: some View {
        if splitVM.panes.isEmpty {
            emptyState
        } else if splitVM.panes.count == 1, let pane = splitVM.panes.first {
            terminalPane(pane)
        } else {
            splitLayout
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No terminal sessions")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open a connection from the sidebar to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func terminalPane(_ pane: SplitPaneViewModel.Pane) -> some View {
        TerminalView(viewModel: pane.viewModel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(4)
            .background {
                Color.windowBackground(in: .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
    }

    private var splitLayout: some View {
        let isHorizontal = splitVM.direction == .horizontal
        return Group {
            if isHorizontal {
                HStack(spacing: 0) {
                    panesContent
                }
            } else {
                VStack(spacing: 0) {
                    panesContent
                }
            }
        }
    }

    private var panesContent: some View {
        ForEach(splitVM.panes) { pane in
            TerminalView(viewModel: pane.viewModel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(2)
        }
    }
}

// Helper: window background color by color scheme
extension Color {
    static func windowBackground(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.95)
    }
}
