import AppKit

private enum LibraryBrowserFilter: String, CaseIterable {
    case all = "All Media"
    case continueWatching = "Continue Watching"
    case favorites = "Favorites"
    case unwatched = "Unwatched"
    case streams = "Streams"
    case missing = "Missing Files"
}

final class LibraryBrowserWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let stateStore: PlaybackStateStore
    private let onOpen: (MediaItem) -> Void
    private let searchField = NSSearchField()
    private let filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No indexed media matches this view.")
    private let countLabel = NSTextField(labelWithString: "0 items")
    private var allItems: [MediaItem] = []
    private var visibleItems: [MediaItem] = []

    init(stateStore: PlaybackStateStore, onOpen: @escaping (MediaItem) -> Void) {
        self.stateStore = stateStore
        self.onOpen = onOpen

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Media Library"
        window.minSize = NSSize(width: 620, height: 380)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        reloadLibrary()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func reloadLibrary() {
        allItems = stateStore.indexedLibraryItems()
        applyFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleItems.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let item = visibleItems[row]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let label = cell.textField ?? NSTextField(labelWithString: "")
        if label.superview == nil {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch identifier.rawValue {
        case "title":
            label.stringValue = item.title
        case "type":
            label.stringValue = item.isNetworkStream ? "STREAM" : item.fileExtension.uppercased()
        default:
            label.stringValue = statusText(for: item)
        }
        return cell
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        let title = NSTextField(labelWithString: "Media Library")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        searchField.placeholderString = "Search title, type, or location"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged(_:))
        searchField.setAccessibilityLabel("Search media library")

        filterPopup.addItems(withTitles: LibraryBrowserFilter.allCases.map(\.rawValue))
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged(_:))
        filterPopup.setAccessibilityLabel("Library filter")

        let refreshButton = NSButton()
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh library")
        refreshButton.bezelStyle = .texturedRounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))
        refreshButton.toolTip = "Refresh library"
        refreshButton.setAccessibilityLabel("Refresh library")

        let openButton = NSButton(title: "Open Selected", target: self, action: #selector(openSelected(_:)))
        openButton.bezelStyle = .rounded

        let toolbar = NSStackView(views: [title, NSView(), searchField, filterPopup, refreshButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 10
        title.setContentHuggingPriority(.required, for: .horizontal)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        filterPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected(_:))
        tableView.setAccessibilityLabel("Indexed media library")
        for (identifier, title, width) in [("title", "Title", 390.0), ("type", "Type", 90.0), ("status", "Status", 210.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "title" ? 180 : 70
            tableView.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let footer = NSStackView(views: [countLabel, NSView(), openButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        for view in [toolbar, scroll, emptyLabel, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    @objc private func filterChanged(_ sender: Any?) {
        applyFilter()
    }

    @objc private func refresh(_ sender: Any?) {
        reloadLibrary()
    }

    @objc private func openSelected(_ sender: Any?) {
        let row = tableView.selectedRow
        guard visibleItems.indices.contains(row) else { return }
        onOpen(visibleItems[row])
    }

    private func applyFilter() {
        let search = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filter = LibraryBrowserFilter(rawValue: filterPopup.selectedItem?.title ?? "") ?? .all
        visibleItems = allItems.filter { item in
            let matchesSearch = search.isEmpty
                || item.title.lowercased().contains(search)
                || item.fileExtension.lowercased().contains(search)
                || MediaPersistence.storageString(for: item.url).lowercased().contains(search)
            guard matchesSearch else { return false }
            let record = stateStore.mediaLibraryRecord(for: item)
            switch filter {
            case .all: return true
            case .continueWatching: return stateStore.position(for: item) > 5
            case .favorites: return record.isFavorite
            case .unwatched: return !record.isWatched
            case .streams: return item.isNetworkStream
            case .missing: return item.url.isFileURL && !FileManager.default.fileExists(atPath: item.url.path)
            }
        }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        tableView.reloadData()
        emptyLabel.isHidden = !visibleItems.isEmpty
        countLabel.stringValue = "\(visibleItems.count) of \(allItems.count) items"
    }

    private func statusText(for item: MediaItem) -> String {
        if item.url.isFileURL && !FileManager.default.fileExists(atPath: item.url.path) {
            return "Missing file"
        }
        let record = stateStore.mediaLibraryRecord(for: item)
        var values: [String] = []
        if record.isFavorite { values.append("Favorite") }
        if record.isWatched { values.append("Watched") }
        let position = stateStore.position(for: item)
        if position > 5 { values.append("Resume \(formatTime(position))") }
        return values.isEmpty ? "Available" : values.joined(separator: " | ")
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
