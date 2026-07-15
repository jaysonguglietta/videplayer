import AppKit

final class SettingsWindowController: NSWindowController {
    private let stateStore = PlaybackStateStore(libraryDatabase: LibraryDatabase.shared)
    private let onPreferencesChanged: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onClearHistory: () -> Void
    private let enterpriseTextView = NSTextView()

    init(
        onPreferencesChanged: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.onPreferencesChanged = onPreferencesChanged
        self.onCheckForUpdates = onCheckForUpdates
        self.onClearHistory = onClearHistory

        let tabs = NSTabViewController()
        tabs.title = "Video Player Settings"
        let window = NSWindow(contentViewController: tabs)
        window.title = "Video Player Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 660, height: 430))
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabs.addTabViewItem(tab(title: "Playback", view: makePlaybackView()))
        tabs.addTabViewItem(tab(title: "Subtitles", view: makeSubtitleView()))
        tabs.addTabViewItem(tab(title: "Library & Privacy", view: makeLibraryView()))
        tabs.addTabViewItem(tab(title: "Updates", view: makeUpdatesView()))
        tabs.addTabViewItem(tab(title: "Enterprise", view: makeEnterpriseView()))
        window.title = "Video Player Settings"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        refreshEnterpriseStatus()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makePlaybackView() -> NSView {
        let volume = NSSlider(value: stateStore.loadVolume(default: 70), minValue: 0, maxValue: 200, target: self, action: #selector(volumeChanged(_:)))
        volume.numberOfTickMarks = 5
        volume.allowsTickMarkValuesOnly = false
        volume.setAccessibilityLabel("Default playback volume")

        let speed = NSPopUpButton(frame: .zero, pullsDown: false)
        speed.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speed.selectItem(withTitle: stateStore.loadSpeedTitle() ?? "1x")
        speed.target = self
        speed.action = #selector(speedChanged(_:))
        speed.setAccessibilityLabel("Default playback speed")

        let audio = NSPopUpButton(frame: .zero, pullsDown: false)
        audio.addItems(withTitles: AudioPreset.allCases.map(\.rawValue))
        audio.selectItem(withTitle: stateStore.loadAudioPreset() ?? AudioPreset.flat.rawValue)
        audio.target = self
        audio.action = #selector(audioPresetChanged(_:))
        audio.setAccessibilityLabel("Default audio preset")

        return formView(
            title: "Playback Defaults",
            subtitle: "These defaults apply unless a media-specific playback profile overrides them.",
            rows: [
                ("Volume (0-200%)", volume),
                ("Playback speed", speed),
                ("Audio preset", audio)
            ]
        )
    }

    private func makeSubtitleView() -> NSView {
        let preferences = stateStore.loadSubtitlePreferences()
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: SubtitlePreferences.SelectionMode.allCases.map(\.rawValue))
        mode.selectItem(withTitle: preferences.selectionMode.rawValue)
        mode.identifier = NSUserInterfaceItemIdentifier("subtitle-mode")
        let language = NSTextField(string: preferences.preferredLanguage)
        language.identifier = NSUserInterfaceItemIdentifier("subtitle-language")
        language.placeholderString = "en"
        let style = NSPopUpButton(frame: .zero, pullsDown: false)
        style.addItems(withTitles: SubtitlePreferences.StylePreset.allCases.map(\.rawValue))
        style.selectItem(withTitle: preferences.stylePreset.rawValue)
        style.identifier = NSUserInterfaceItemIdentifier("subtitle-style")
        let save = NSButton(title: "Save Subtitle Defaults", target: self, action: #selector(saveSubtitlePreferences(_:)))
        save.bezelStyle = .rounded
        save.identifier = NSUserInterfaceItemIdentifier("subtitle-save")

        return formView(
            title: "Subtitle Defaults",
            subtitle: "Choose automatic selection, a preferred language, and a readable style preset.",
            rows: [
                ("Selection mode", mode),
                ("Preferred language", language),
                ("Style", style),
                ("", save)
            ]
        )
    }

    private func makeLibraryView() -> NSView {
        let policy = EnterprisePolicy.snapshot()
        let history = checkbox(
            title: "Save playback history and library state",
            state: stateStore.savePlaybackHistoryEnabled(),
            action: #selector(historyChanged(_:)),
            enabled: !policy.forceDisablePlaybackHistory
        )
        let clearOnQuit = checkbox(
            title: "Clear playback history when Video Player quits",
            state: stateStore.clearHistoryOnQuitEnabled(),
            action: #selector(clearOnQuitChanged(_:)),
            enabled: !policy.forceClearHistoryOnQuit
        )
        let privateStreams = checkbox(
            title: "Allow private and local network streams",
            state: stateStore.privateNetworkStreamsEnabled(),
            action: #selector(privateStreamsChanged(_:)),
            enabled: !policy.forceBlockPrivateNetworkStreams
        )
        let externalEngines = checkbox(
            title: "Enable trusted VLC/mpv engines",
            state: stateStore.externalMediaEnginesEnabled(),
            action: #selector(externalEnginesChanged(_:)),
            enabled: AppSecurityPolicy.externalMediaEnginesAvailable && !policy.forceDisableExternalMediaEngines
        )
        let revealMetadata = NSButton(title: "Reveal Saved Metadata", target: self, action: #selector(revealMetadata(_:)))
        let clearCredentials = NSButton(title: "Remove Stream Credentials", target: self, action: #selector(clearStreamCredentials(_:)))
        clearCredentials.isEnabled = !StreamCredentialStore.storedHosts().isEmpty
        let clearHistory = NSButton(title: "Clear All Playback History", target: self, action: #selector(clearHistory(_:)))
        for button in [revealMetadata, clearCredentials, clearHistory] { button.bezelStyle = .rounded }

        let stack = contentStack(
            title: "Library and Privacy",
            subtitle: "History is off by default. Managed preferences can lock these controls."
        )
        [history, clearOnQuit, privateStreams, externalEngines].forEach(stack.addArrangedSubview)
        let buttons = NSStackView(views: [revealMetadata, clearCredentials, clearHistory, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
        return container(for: stack)
    }

    private func makeUpdatesView() -> NSView {
        let policy = EnterprisePolicy.snapshot()
        let channel = NSPopUpButton(frame: .zero, pullsDown: false)
        channel.addItems(withTitles: UserUpdateChannel.allCases.map(\.rawValue))
        channel.selectItem(withTitle: AppPreferences.updateChannel().rawValue)
        channel.target = self
        channel.action = #selector(updateChannelChanged(_:))
        channel.isEnabled = ["github", ""].contains(policy.updateChannel)
        channel.setAccessibilityLabel("Update channel")
        let check = NSButton(title: "Check for Updates", target: self, action: #selector(checkForUpdates(_:)))
        check.bezelStyle = .rounded
        check.isEnabled = !policy.disableUpdateChecks && policy.updateChannel != "mdm"
        return formView(
            title: "Software Updates",
            subtitle: "Stable excludes prereleases. Beta accepts signed GitHub prereleases. Managed update settings take precedence.",
            rows: [
                ("Channel", channel),
                ("", check)
            ]
        )
    }

    private func makeEnterpriseView() -> NSView {
        enterpriseTextView.isEditable = false
        enterpriseTextView.isSelectable = true
        enterpriseTextView.drawsBackground = false
        enterpriseTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = enterpriseTextView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        enterpriseTextView.autoresizingMask = [.width]
        let stack = contentStack(
            title: "Enterprise Configuration",
            subtitle: "This read-only view reflects effective MDM policy and license state."
        )
        stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 280).isActive = true
        return container(for: stack)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        stateStore.saveVolume(sender.doubleValue)
        onPreferencesChanged()
    }

    @objc private func speedChanged(_ sender: NSPopUpButton) {
        stateStore.saveSpeedTitle(sender.selectedItem?.title ?? "1x")
        onPreferencesChanged()
    }

    @objc private func audioPresetChanged(_ sender: NSPopUpButton) {
        stateStore.saveAudioPreset(sender.selectedItem?.title ?? AudioPreset.flat.rawValue)
        onPreferencesChanged()
    }

    @objc private func saveSubtitlePreferences(_ sender: NSButton) {
        guard let root = sender.window?.contentView,
              let mode = findView(in: root, identifier: "subtitle-mode") as? NSPopUpButton,
              let language = findView(in: root, identifier: "subtitle-language") as? NSTextField,
              let style = findView(in: root, identifier: "subtitle-style") as? NSPopUpButton
        else {
            return
        }
        let preferences = SubtitlePreferences(
            selectionMode: SubtitlePreferences.SelectionMode(rawValue: mode.selectedItem?.title ?? "") ?? .automatic,
            preferredLanguage: language.stringValue,
            stylePreset: SubtitlePreferences.StylePreset(rawValue: style.selectedItem?.title ?? "") ?? .system
        )
        stateStore.saveSubtitlePreferences(preferences)
        onPreferencesChanged()
    }

    @objc private func historyChanged(_ sender: NSButton) {
        stateStore.setSavePlaybackHistoryEnabled(sender.state == .on)
        onPreferencesChanged()
    }

    @objc private func clearOnQuitChanged(_ sender: NSButton) {
        stateStore.setClearHistoryOnQuitEnabled(sender.state == .on)
        onPreferencesChanged()
    }

    @objc private func privateStreamsChanged(_ sender: NSButton) {
        stateStore.setPrivateNetworkStreamsEnabled(sender.state == .on)
        onPreferencesChanged()
    }

    @objc private func externalEnginesChanged(_ sender: NSButton) {
        stateStore.setExternalMediaEnginesEnabled(sender.state == .on)
        onPreferencesChanged()
    }

    @objc private func updateChannelChanged(_ sender: NSPopUpButton) {
        guard let channel = UserUpdateChannel(rawValue: sender.selectedItem?.title ?? "") else { return }
        AppPreferences.setUpdateChannel(channel)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        onCheckForUpdates()
    }

    @objc private func revealMetadata(_ sender: Any?) {
        let directory = MediaMetadataCache.defaultDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func clearHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear All Playback History?"
        alert.informativeText = "This removes saved playlists, positions, library records, profiles, bookmarks, and metadata references. Media files are not deleted."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onClearHistory()
        onPreferencesChanged()
    }

    @objc private func clearStreamCredentials(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove Saved Stream Credentials?"
        alert.informativeText = "Passwords saved by Video Player will be removed from Keychain. Stream bookmarks remain available."
        alert.addButton(withTitle: "Remove Credentials")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        StreamCredentialStore.removeAll()
        (sender as? NSButton)?.isEnabled = false
    }

    private func refreshEnterpriseStatus() {
        enterpriseTextView.string = PlaybackDiagnostics.enterpriseStatusReport(
            policy: EnterprisePolicy.snapshot(),
            licenseStatus: EnterpriseLicenseManager.status()
        )
    }

    private func checkbox(title: String, state: Bool, action: Selector, enabled: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state ? .on : .off
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
        return button
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = view
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        return item
    }

    private func formView(title: String, subtitle: String, rows: [(String, NSView)]) -> NSView {
        let stack = contentStack(title: title, subtitle: subtitle)
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 300
        stack.addArrangedSubview(grid)
        return container(for: stack)
    }

    private func contentStack(title: String, subtitle: String) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: subtitle)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        let stack = NSStackView(views: [heading, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        return stack
    }

    private func container(for stack: NSStackView) -> NSView {
        let view = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])
        return view
    }

    private func findView(in root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        for child in root.subviews {
            if let match = findView(in: child, identifier: identifier) { return match }
        }
        return nil
    }
}
