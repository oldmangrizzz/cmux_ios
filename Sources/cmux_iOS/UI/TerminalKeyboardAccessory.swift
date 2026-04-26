import UIKit

/// A keyboard accessory toolbar for the terminal, providing keys that are
/// awkward or impossible to type on the iOS software keyboard.
final class TerminalInputAccessoryView: UIView {
    private let onKey: (String) -> Void
    private let onToggleCtrl: () -> Void
    private let onToggleMeta: () -> Void
    private var isCtrlActive = false
    private var isMetaActive = false

    init(onKey: @escaping (String) -> Void, onToggleCtrl: @escaping () -> Void, onToggleMeta: @escaping () -> Void) {
        self.onKey = onKey
        self.onToggleCtrl = onToggleCtrl
        self.onToggleMeta = onToggleMeta
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        backgroundColor = UIColor.systemGray6
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceHorizontal = true
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 44)
        ])

        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.heightAnchor)
        ])

        let keys: [(String, String)] = [
            ("ESC", "\u{001b}"),
            ("TAB", "\t"),
            ("/", "/"),
            ("-", "-"),
            ("|", "|"),
            ("~", "~"),
            ("`", "`"),
            ("\\", "\\"),
            ("{", "{"),
            ("}", "}"),
            ("[", "["),
            ("]", "]"),
            ("\u{2190}", "\u{001b}[D"), // left arrow (CSI D)
            ("\u{2191}", "\u{001b}[A"), // up arrow (CSI A)
            ("\u{2193}", "\u{001b}[B"), // down arrow (CSI B)
            ("\u{2192}", "\u{001b}[C"), // right arrow (CSI C)
            ("Home", "\u{001b}[H"),
            ("End", "\u{001b}[F"),
            ("PgUp", "\u{001b}[5~"),
            ("PgDn", "\u{001b}[6~"),
        ]

        for (label, value) in keys {
            let btn = makeButton(title: label)
            btn.addAction(UIAction(handler: { [weak self] _ in
                self?.onKey(value)
            }), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        let ctrlBtn = makeButton(title: "Ctrl")
        ctrlBtn.addAction(UIAction(handler: { [weak self] _ in
            self?.isCtrlActive.toggle()
            self?.updateToggle(btn: ctrlBtn, active: self?.isCtrlActive ?? false)
            self?.onToggleCtrl()
        }), for: .touchUpInside)
        stack.addArrangedSubview(ctrlBtn)

        let metaBtn = makeButton(title: "Meta")
        metaBtn.addAction(UIAction(handler: { [weak self] _ in
            self?.isMetaActive.toggle()
            self?.updateToggle(btn: metaBtn, active: self?.isMetaActive ?? false)
            self?.onToggleMeta()
        }), for: .touchUpInside)
        stack.addArrangedSubview(metaBtn)
    }

    private func makeButton(title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .label
        config.background.backgroundColor = .secondarySystemBackground
        config.cornerStyle = .small
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return btn
    }

    private func updateToggle(btn: UIButton, active: Bool) {
        var config = btn.configuration ?? .plain()
        config.baseForegroundColor = active ? .systemBackground : .label
        config.background.backgroundColor = active ? .systemBlue : .secondarySystemBackground
        btn.configuration = config
    }
}
