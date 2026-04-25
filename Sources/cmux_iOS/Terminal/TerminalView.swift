import SwiftUI
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's TerminalView.
struct TerminalView: UIViewRepresentable {
    typealias UIViewType = SwiftTerm.TerminalView

    @ObservedObject var viewModel: TerminalViewModel

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let term = SwiftTerm.TerminalView()
        term.terminalDelegate = context.coordinator
        applyTheme(to: term)
        return term
    }

    @MainActor
    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        applyTheme(to: uiView)
        context.coordinator.maybeRegister(uiView)
    }

    @MainActor
    private func applyTheme(to term: SwiftTerm.TerminalView) {
        let theme = viewModel.theme
        let palette: [SwiftTerm.Color] = [
            SwiftTerm.Color(theme.black),
            SwiftTerm.Color(theme.red),
            SwiftTerm.Color(theme.green),
            SwiftTerm.Color(theme.yellow),
            SwiftTerm.Color(theme.blue),
            SwiftTerm.Color(theme.magenta),
            SwiftTerm.Color(theme.cyan),
            SwiftTerm.Color(theme.white),
            SwiftTerm.Color(theme.brightBlack),
            SwiftTerm.Color(theme.brightRed),
            SwiftTerm.Color(theme.brightGreen),
            SwiftTerm.Color(theme.brightYellow),
            SwiftTerm.Color(theme.brightBlue),
            SwiftTerm.Color(theme.brightMagenta),
            SwiftTerm.Color(theme.brightCyan),
            SwiftTerm.Color(theme.brightWhite),
        ]
        term.installColors(palette)
        term.getTerminal().foregroundColor = SwiftTerm.Color(theme.foreground)
        term.getTerminal().backgroundColor = SwiftTerm.Color(theme.background)
        term.getTerminal().setCursorStyle(.blinkBlock)
        term.nativeBackgroundColor = UIColor(theme.background)
        term.nativeForegroundColor = UIColor(theme.foreground)
    }

    @MainActor
    class Coordinator: TerminalViewDelegate {
        let viewModel: TerminalViewModel
        /// Set once to avoid re-setting terminalView after the initial binding.
        private var didRegister = false

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        /// Registers the terminal view on the view model exactly once.
        func maybeRegister(_ term: SwiftTerm.TerminalView) {
            if !didRegister {
                viewModel.terminalView = term
                didRegister = true
            }
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            viewModel.columns = newCols
            viewModel.rows = newRows
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let data = Data(data)
            viewModel.sendInput(data)
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            viewModel.session.title = title
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}

        func bell(source: SwiftTerm.TerminalView) {}

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}

// MARK: - UIColor from hex string

#if canImport(UIKit)
import UIKit

extension UIColor {
    convenience init(_ hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            (r, g, b, a) = (CGFloat((int >> 16) & 0xFF) / 255,
                            CGFloat((int >> 8) & 0xFF) / 255,
                            CGFloat(int & 0xFF) / 255, 1)
        case 8:
            (r, g, b, a) = (CGFloat((int >> 24) & 0xFF) / 255,
                            CGFloat((int >> 16) & 0xFF) / 255,
                            CGFloat((int >> 8) & 0xFF) / 255,
                            CGFloat(int & 0xFF) / 255)
        default:
            (r, g, b, a) = (0, 0, 0, 1)
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif

// MARK: - SwiftTerm Color from hex string

extension SwiftTerm.Color {
    convenience init(_ hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt16
        switch hex.count {
        case 6:
            r = UInt16((int >> 16) & 0xFF)
            g = UInt16((int >> 8) & 0xFF)
            b = UInt16(int & 0xFF)
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
