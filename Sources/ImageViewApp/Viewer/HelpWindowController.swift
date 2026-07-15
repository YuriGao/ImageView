import AppKit

@MainActor
final class HelpWindowController: NSWindowController, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let textView = NSTextView()
    private let preferredLanguages: [String]
    private var entries: [String] = []

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        self.preferredLanguages = preferredLanguages
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppStrings.text("menu.help.imageView", preferredLanguages: preferredLanguages)
        super.init(window: window)
        buildView()
    }

    private func text(_ key: String) -> String {
        AppStrings.text(key, preferredLanguages: preferredLanguages)
    }

    private func buildView() {
        entries = text("help.content")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        searchField.placeholderString = text("help.searchPlaceholder")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.setAccessibilityLabel(searchField.placeholderString)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = .systemFont(ofSize: 13)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = NSView()
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        window?.contentView = contentView
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
        render(query: "")
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        render(query: sender.stringValue)
    }

    private func render(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = trimmed.isEmpty
            ? entries
            : entries.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        textView.string = visible.isEmpty ? text("help.noResults") : visible.joined(separator: "\n\n")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
