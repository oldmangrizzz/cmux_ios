import SwiftUI

/// Manages terminal tabs — each tab has its own split pane layout.
@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTab: Tab.ID?

    struct Tab: Identifiable {
        let id = UUID()
        var title: String
        let splitVM: SplitPaneViewModel
    }

    var selectedSplitVM: SplitPaneViewModel? {
        guard let id = selectedTab else { return nil }
        return tabs.first { $0.id == id }?.splitVM
    }

    func newTab(title: String = "Terminal") -> SplitPaneViewModel {
        let splitVM = SplitPaneViewModel()
        let tab = Tab(title: title, splitVM: splitVM)
        tabs.append(tab)
        selectedTab = tab.id
        return splitVM
    }

    func closeTab(id: Tab.ID) {
        tabs.removeAll { $0.id == id }
        if selectedTab == id {
            selectedTab = tabs.last?.id
        }
    }
}

/// Tab bar along the top, styled after cmux's compact tabs.
struct TerminalTabBarView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var showSidebar: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                sidebarToggle
                ForEach(tabManager.tabs) { tab in
                    tabPill(tab)
                }
                newTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                showSidebar.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .padding(.trailing, 4)
    }

    private func tabPill(_ tab: TabManager.Tab) -> some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
            Button {
                let paneVM = tab.splitVM
                if paneVM.panes.isEmpty {
                    tabManager.closeTab(id: tab.id)
                } else {
                    paneVM.panes.forEach { $0.viewModel.disconnect() }
                    tabManager.closeTab(id: tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(tabManager.selectedTab == tab.id ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if tabManager.selectedTab == tab.id {
                Capsule()
                    .fill(.regularMaterial)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { tabManager.selectedTab = tab.id }
    }

    private var newTabButton: some View {
        Button {
            _ = tabManager.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .buttonStyle(.plain)
    }
}
