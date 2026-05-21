import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

final class PlayerViewController: NSViewController {
    private let maximumVolume = 200.0
    private let defaultVolume = 70.0
    private let maximumScannedMediaFiles = 5_000
    private let maximumEnumeratedFolderItems = 20_000
    private let playlistImportContentTypes = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
    private let playlistExportContentTypes = ["m3u8"].compactMap { UTType(filenameExtension: $0) }
    private let avPlayer = AVPlayer()
    private let vlcBridge = VLCBridge()
    private let mpvBridge = MPVBridge()
    private let stateStore = PlaybackStateStore()
    private let nativeExtensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf"]
    private let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mk4", "mkv", "avi", "webm", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts",
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "ogg", "opus"
    ]
    private let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt"]

    private var playlist: [MediaItem] = []
    private var currentIndex: Int?
    private var currentEngine: PlaybackEngine = .none
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var codecTimer: Timer?
    private var nativePlaybackInspectionTask: Task<Void, Never>?
    private var nativeVideoWatchdogTask: Task<Void, Never>?
    private var hudTimer: Timer?
    private var scrollWheelMonitor: Any?
    private var keyDownMonitor: Any?
    private var isScrubbing = false
    private var isMuted = false
    private var volumeBeforeMute = 70.0
    private var codecTickCount = 0
    private var isUpdatingTrackMenus = false
    private var loopStart: Double?
    private var loopEnd: Double?
    private var currentAudioPreset: AudioPreset = .flat
    private var isMiniPlayer = false
    private var isTheaterMode = false
    private var savedWindowFrame: NSRect?
    private var savedWindowLevel: NSWindow.Level = .normal
    private var metadataRequestID = 0
    private var playbackRequestID = 0
    private var playlistFilter = ""
    private var playlistSortMode: PlaylistSortMode = .currentOrder
    private var networkStreamResolutions: [String: Set<String>] = [:]
    private var currentVideoAdjustments = VideoAdjustments()
    private var videoAdjustmentPanel: NSPanel?
    private var videoAdjustmentSliders: [VideoAdjustmentKey: NSSlider] = [:]
    private var libraryPanel: NSPanel?
    private weak var libraryFoldersStack: NSStackView?

    private let playerView = AVPlayerView()
    private let vlcVideoSurface = NSView()
    private weak var splitView: NSSplitView?
    private weak var sidebarView: NSView?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private weak var playerAreaView: NSView?
    private let tableView = NSTableView()
    private let playlistSearchField = NSSearchField()
    private let playlistSortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var removePlaylistButton: NSButton?
    private weak var clearPlaylistButton: NSButton?
    private let metadataTextView = NSTextField(labelWithString: "Select a media item to inspect it before playback.")
    private let emptyStateContainer = NSStackView()
    private let emptyStateLabel = NSTextField(labelWithString: "Drop media files here")
    private let emptyStateSubtitleLabel = NSTextField(labelWithString: "Open a local file, add a folder, or paste a public stream URL.")
    private let emptyStateOpenButton = NSButton(title: "Open Media", target: nil, action: nil)
    private let emptyStateStreamButton = NSButton(title: "Open Stream", target: nil, action: nil)
    private let hudLabel = NSTextField(labelWithString: "")
    private let nowPlayingLabel = NSTextField(labelWithString: "Ready")
    private let engineLabel = NSTextField(labelWithString: "")
    private let currentTimeLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let playPauseButton = NSButton()
    private let sidebarButton = NSButton()
    private let volumeSlider = NSSlider(value: 70, minValue: 0, maxValue: 200, target: nil, action: nil)
    private let volumeLabel = NSTextField(labelWithString: "70%")
    private let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioTrackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioPresetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioDelayStepper = NSStepper()
    private let audioDelayLabel = NSTextField(labelWithString: "0.0s")
    private let subtitleTrackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let subtitleDelayStepper = NSStepper()
    private let subtitleDelayLabel = NSTextField(labelWithString: "0.0s")

    override func loadView() {
        let rootView = DropView()
        rootView.dropDelegate = self
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
        buildInterface(in: rootView)
        configurePlayer()
        configureVLCEvents()
        configureScrollWheelVolume()
        configureKeyboardShortcuts()
        restorePersistentState()
        refreshControls()
    }

    deinit {
        if stateStore.clearHistoryOnQuitEnabled() {
            stateStore.clearPlaybackHistory()
        } else {
            saveCurrentPosition()
            savePlaylistState()
        }
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        nativePlaybackInspectionTask?.cancel()
        nativeVideoWatchdogTask?.cancel()
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
        }
        codecTimer?.invalidate()
        hudTimer?.invalidate()
        vlcBridge.stop()
        mpvBridge.stop()
    }

    @objc func openFilesPanel(replacePlaylist: Bool) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("File browsing disabled in kiosk mode")
            return
        }
        let panel = NSOpenPanel()
        panel.title = replacePlaylist ? "Open Media" : "Add Media"
        panel.message = "Choose video or audio files, folders, subtitles, or playlists of files."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }
        addMedia(from: panel.urls, replacePlaylist: replacePlaylist, autoplay: false)
    }

    func openMedia(_ urls: [URL], replacePlaylist: Bool) {
        addMedia(from: urls, replacePlaylist: replacePlaylist, autoplay: false)
    }

    func importPlaylistPanel(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("Playlist import disabled in kiosk mode")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import Playlist"
        panel.message = "Choose an M3U or M3U8 playlist file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = playlistImportContentTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        showHUD("Importing playlist")
        let shouldReplacePlaylist = playlist.isEmpty
        Task { [weak self] in
            await self?.importPlaylist(from: url, replacePlaylist: shouldReplacePlaylist)
        }
    }

    func exportPlaylistPanel(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("Playlist export disabled in kiosk mode")
            return
        }
        guard !playlist.isEmpty else {
            showHUD("Playlist is empty")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Playlist"
        panel.message = "Save the current playlist as an M3U8 file."
        panel.nameFieldStringValue = "Video Player Playlist.m3u8"
        panel.allowedContentTypes = playlistExportContentTypes
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try exportedPlaylistText().write(to: url, atomically: true, encoding: .utf8)
            showHUD("Playlist exported")
        } catch {
            showPlaylistFileError(
                title: "Could Not Export Playlist",
                detail: "The playlist could not be written to the selected location. \(error.localizedDescription)"
            )
        }
    }

    @objc func openNetworkStreamDialog(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("Streams are managed in kiosk mode")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open Network Stream"
        alert.informativeText = "Enter an HTTP, HTTPS, RTSP, or HLS stream URL."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "https://example.com/stream.m3u8"
        input.setAccessibilityLabel("Network stream URL")
        input.setAccessibilityHelp("Enter a public HTTP, HTTPS, RTSP, or HLS media stream URL.")
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let streamValue = input.stringValue
        let allowPrivateNetworkHosts = stateStore.privateNetworkStreamsEnabled()
        showHUD("Checking stream")
        Task { [weak self] in
            let stream = await NetworkStreamValidator.validatedStream(
                from: streamValue,
                allowPrivateNetworkHosts: allowPrivateNetworkHosts
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let stream else {
                    self.showHUD("Use public HTTP, HTTPS, RTSP, or HLS")
                    return
                }
                self.rememberValidatedNetworkStream(stream)
                let url = stream.url
                self.addMediaItems([MediaItem(url: url)], replacePlaylist: self.playlist.isEmpty, autoplay: false)
            }
        }
    }

    @objc func openSubtitlePanel(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Load Subtitle"
        panel.message = "Choose an SRT, ASS, SSA, or VTT subtitle file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadSubtitle(url)
    }

    func recentMediaItems() -> [MediaItem] {
        stateStore.loadRecentMedia()
    }

    func openRecentMedia(at index: Int) {
        let items = stateStore.loadRecentMedia()
        guard items.indices.contains(index) else { return }
        addMediaItems([items[index]], replacePlaylist: true, autoplay: false)
        showHUD("Recent item loaded")
    }

    func clearRecentMedia() {
        stateStore.clearRecentMedia()
        showHUD("Recent files cleared")
    }

    @objc func removeSelectedPlaylistItems(_ sender: Any? = nil) {
        let selectedIndexes = selectedPlaylistIndices()
        guard !selectedIndexes.isEmpty else {
            showHUD("Select playlist items first")
            return
        }

        let removedVisibleRows = tableView.selectedRowIndexes
        let activeItem = currentItem
        let removesCurrentItem = currentIndex.map { selectedIndexes.contains($0) } ?? false
        if removesCurrentItem {
            stopPlayback()
        }

        playlist = PlaylistWorkflow.removing(playlist, indexes: selectedIndexes)

        if removesCurrentItem {
            currentIndex = nil
            metadataRequestID += 1
            metadataTextView.stringValue = "Select a media item to inspect it before playback."
            updateNowPlaying(title: "Ready", detail: "")
        } else if let activeItem {
            currentIndex = playlist.firstIndex(of: activeItem)
        }

        tableView.reloadData()
        selectNearestPlaylistRow(afterRemovingVisibleRows: removedVisibleRows)
        updateEmptyState()
        refreshPlaylistActionStates()
        savePlaylistState()
        showHUD("Removed \(selectedIndexes.count) item\(selectedIndexes.count == 1 ? "" : "s")")
    }

    func savePlaybackHistoryEnabled() -> Bool {
        stateStore.savePlaybackHistoryEnabled()
    }

    @objc func toggleSavePlaybackHistory(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().forceDisablePlaybackHistory else {
            stateStore.setSavePlaybackHistoryEnabled(false)
            showHUD("History disabled by policy")
            return
        }
        let enabled = !stateStore.savePlaybackHistoryEnabled()
        stateStore.setSavePlaybackHistoryEnabled(enabled)
        if !enabled {
            playlist.removeAll()
            currentIndex = nil
            tableView.reloadData()
            updateEmptyState()
            refreshPlaylistActionStates()
        }
        showHUD(enabled ? "History saving on" : "History saving off")
    }

    func clearHistoryOnQuitEnabled() -> Bool {
        stateStore.clearHistoryOnQuitEnabled()
    }

    @objc func toggleClearHistoryOnQuit(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().forceClearHistoryOnQuit else {
            stateStore.setClearHistoryOnQuitEnabled(true)
            showHUD("Clear on quit is managed")
            return
        }
        let enabled = !stateStore.clearHistoryOnQuitEnabled()
        stateStore.setClearHistoryOnQuitEnabled(enabled)
        showHUD(enabled ? "History clears on quit" : "History kept after quit")
    }

    func privateNetworkStreamsEnabled() -> Bool {
        stateStore.privateNetworkStreamsEnabled()
    }

    @objc func togglePrivateNetworkStreams(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().forceBlockPrivateNetworkStreams else {
            stateStore.setPrivateNetworkStreamsEnabled(false)
            showHUD("Private streams blocked by policy")
            return
        }
        let enabled = !stateStore.privateNetworkStreamsEnabled()
        stateStore.setPrivateNetworkStreamsEnabled(enabled)
        showHUD(enabled ? "Private streams allowed" : "Private streams blocked")
    }

    func externalMediaEnginesEnabled() -> Bool {
        stateStore.externalMediaEnginesEnabled()
    }

    func externalMediaEnginesAvailable() -> Bool {
        AppSecurityPolicy.externalMediaEnginesAvailable
    }

    @objc func toggleExternalMediaEngines(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().forceDisableExternalMediaEngines else {
            stateStore.setExternalMediaEnginesEnabled(false)
            showHUD("External engines disabled by policy")
            return
        }
        guard AppSecurityPolicy.externalMediaEnginesAvailable else {
            stateStore.setExternalMediaEnginesEnabled(false)
            AppLogger.warning("User tried to enable external engines, but this build does not allow them")
            showHUD("External engines unavailable in this build")
            return
        }
        let enabled = !stateStore.externalMediaEnginesEnabled()
        stateStore.setExternalMediaEnginesEnabled(enabled)
        AppLogger.info("External media engines toggled enabled=\(enabled)", flush: true)
        if !enabled, currentEngine == .vlc || currentEngine == .mpv {
            stopPlayback()
        }
        showHUD(enabled ? "External engines enabled" : "External engines disabled")
    }

    @objc func clearAllPlaybackHistory(_ sender: Any? = nil) {
        stateStore.clearPlaybackHistory()
        playlist.removeAll()
        currentIndex = nil
        tableView.reloadData()
        updateEmptyState()
        refreshPlaylistActionStates()
        showHUD("Playback history cleared")
    }

    @objc func chooseLibraryFolder(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("Library changes disabled in kiosk mode")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Add Library Folder"
        panel.message = "Choose a folder to scan for media."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let canPersist = stateStore.savePlaybackHistoryEnabled()
        stateStore.addLibraryFolder(url)
        addMedia(from: [url], replacePlaylist: playlist.isEmpty, autoplay: false)
        rebuildLibraryFolderRows()
        showHUD(canPersist ? "Library folder added" : "Folder loaded, not saved")
    }

    @objc func loadLibraryFolders(_ sender: Any? = nil) {
        let folders = stateStore.loadLibraryFolders()
        guard !folders.isEmpty else {
            chooseLibraryFolder(sender)
            return
        }
        addMedia(from: folders, replacePlaylist: true, autoplay: false)
        showHUD("Library loaded")
    }

    @objc func showLibraryManager(_ sender: Any? = nil) {
        guard !EnterprisePolicy.snapshot().kioskModeEnabled else {
            showHUD("Library changes disabled in kiosk mode")
            return
        }
        if let libraryPanel {
            rebuildLibraryFolderRows()
            libraryPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Library Folders"
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let contentView = NSView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        let title = NSTextField(labelWithString: "Media Library")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Save trusted folders, rescan them into the playlist, or remove folders you no longer want remembered.")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping

        let foldersStack = NSStackView()
        foldersStack.translatesAutoresizingMaskIntoConstraints = false
        foldersStack.orientation = .vertical
        foldersStack.spacing = 8
        foldersStack.alignment = .leading
        self.libraryFoldersStack = foldersStack

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = foldersStack
        scrollView.heightAnchor.constraint(equalToConstant: 190).isActive = true

        let addButton = NSButton(title: "Add Folder", target: self, action: #selector(addLibraryFolderFromManager(_:)))
        let loadButton = NSButton(title: "Load All", target: self, action: #selector(loadLibraryFoldersFromManager(_:)))
        let clearButton = NSButton(title: "Remove All", target: self, action: #selector(clearLibraryFoldersFromManager(_:)))
        for button in [addButton, loadButton, clearButton] {
            button.bezelStyle = .rounded
            button.setAccessibilityLabel(button.title)
        }
        let buttonRow = NSStackView(views: [addButton, loadButton, clearButton, NSView()])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(scrollView)
        stack.addArrangedSubview(buttonRow)
        contentView.addSubview(stack)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            foldersStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -18)
        ])

        libraryPanel = panel
        rebuildLibraryFolderRows()
        view.window?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func addLibraryFolderFromManager(_ sender: Any? = nil) {
        chooseLibraryFolder(sender)
    }

    @objc private func loadLibraryFoldersFromManager(_ sender: Any? = nil) {
        loadLibraryFolders(sender)
    }

    @objc private func clearLibraryFoldersFromManager(_ sender: Any? = nil) {
        guard !stateStore.loadLibraryFolders().isEmpty else {
            showHUD("No saved folders")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove All Library Folders?"
        alert.informativeText = "This removes saved folder references only. Media files on disk are not deleted."
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        stateStore.clearLibraryFolders()
        rebuildLibraryFolderRows()
        showHUD("Library folders removed")
    }

    @objc private func removeLibraryFolderFromManager(_ sender: NSButton) {
        let folders = stateStore.loadLibraryFolders()
        guard folders.indices.contains(sender.tag) else { return }
        stateStore.removeLibraryFolder(folders[sender.tag])
        rebuildLibraryFolderRows()
        showHUD("Library folder removed")
    }

    @objc func showPlaybackDiagnostics(_ sender: Any? = nil) {
        showHUD("Building diagnostics")
        Task { [weak self] in
            let report = await self?.currentPlaybackDiagnosticReport()
            await MainActor.run {
                guard let self, let report else { return }
                self.showTextDialog(title: "Playback Diagnostics", text: report.text, height: 420)
            }
        }
    }

    @objc func showEnterpriseStatus(_ sender: Any? = nil) {
        let text = PlaybackDiagnostics.enterpriseStatusReport(
            policy: EnterprisePolicy.snapshot(),
            licenseStatus: EnterpriseLicenseManager.status()
        )
        showTextDialog(title: "Enterprise Status", text: text, height: 440)
    }

    @objc func showReleaseReadiness(_ sender: Any? = nil) {
        showTextDialog(
            title: "Release Readiness",
            text: ReleaseReadiness.report().text,
            height: 460
        )
    }

    @objc func showMediaEngineDoctor(_ sender: Any? = nil) {
        showHUD("Checking engines")
        Task.detached(priority: .utility) {
            let report = MediaEngineDoctor.report()
            await MainActor.run { [weak self] in
                self?.showTextDialog(title: "Playback Engine Doctor", text: report.text, height: 460)
            }
        }
    }

    @objc func exportMDMPolicyProfile(_ sender: Any? = nil) {
        let panel = NSSavePanel()
        panel.title = "Export MDM Policy Profile"
        panel.message = "Save a configuration profile with the current Video Player enterprise policy values."
        panel.nameFieldStringValue = "Video Player Enterprise Policy.mobileconfig"
        if let mobileconfigType = UTType(filenameExtension: "mobileconfig") {
            panel.allowedContentTypes = [mobileconfigType]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = MDMProfileBuilder.mobileconfig(policy: EnterprisePolicy.snapshot())
            try profile.write(to: url, atomically: true, encoding: .utf8)
            showHUD("MDM profile exported")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showTextDialog(title: "MDM Export Failed", text: error.localizedDescription, height: 120)
        }
    }

    @objc func showLicenseStatus(_ sender: Any? = nil) {
        let status = EnterpriseLicenseManager.status()
        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = status.detailLines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Import License")
        if alert.runModal() == .alertSecondButtonReturn {
            importEnterpriseLicense(sender)
        }
    }

    @objc func createEnterpriseActivationRequest(_ sender: Any? = nil) {
        let alert = NSAlert()
        alert.messageText = "Create License Activation Request"
        alert.informativeText = "Enter the license key and requester email. The request file can be sent to support for offline activation."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        let keyField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        keyField.placeholderString = "License key"
        keyField.setAccessibilityLabel("License key")
        let emailField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        emailField.placeholderString = "Requester email"
        emailField.setAccessibilityLabel("Requester email")
        stack.addArrangedSubview(keyField)
        stack.addArrangedSubview(emailField)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showHUD("License key required")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Activation Request"
        panel.nameFieldStringValue = "video-player-activation-request.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let request = EnterpriseActivationManager.activationRequest(
                licenseKey: keyField.stringValue,
                requestedBy: emailField.stringValue
            )
            try EnterpriseActivationManager.writeActivationRequest(request, to: url)
            showHUD("Activation request saved")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showTextDialog(title: "Activation Request Failed", text: error.localizedDescription, height: 120)
        }
    }

    @objc func deactivateEnterpriseLicense(_ sender: Any? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Deactivate Enterprise License?"
        alert.informativeText = "This removes the local license file from this Mac. It does not contact a licensing server."
        alert.addButton(withTitle: "Deactivate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try EnterpriseActivationManager.deactivateLicense()
            showHUD("License deactivated")
        } catch {
            showTextDialog(title: "Deactivate Failed", text: error.localizedDescription, height: 120)
        }
    }

    @objc func showAccessibilityGuide(_ sender: Any? = nil) {
        showTextDialog(title: "Keyboard Shortcuts and Accessibility", text: AccessibilityGuide.text, height: 440)
    }

    @objc func showLibraryReport(_ sender: Any? = nil) {
        let report = LibraryCatalog.report(
            playlist: playlist,
            records: stateStore.mediaLibraryRecords()
        )
        showTextDialog(title: "Library Report", text: report.text, height: 320)
    }

    @objc func toggleFavoriteForSelectedItems(_ sender: Any? = nil) {
        let items = selectedPlaylistIndices().map { playlist[$0] }
        guard !items.isEmpty else {
            showHUD("Select playlist items first")
            return
        }

        for item in items {
            var record = stateStore.mediaLibraryRecord(for: item)
            record.isFavorite.toggle()
            record.updatedAt = Date()
            stateStore.saveMediaLibraryRecord(record, for: item)
        }
        updateMetadataForSelection()
        showHUD("Favorite updated")
    }

    func setWatchedForSelectedItems(_ watched: Bool, sender: Any? = nil) {
        let items = selectedPlaylistIndices().map { playlist[$0] }
        guard !items.isEmpty else {
            showHUD("Select playlist items first")
            return
        }

        for item in items {
            var record = stateStore.mediaLibraryRecord(for: item)
            record.isWatched = watched
            record.updatedAt = Date()
            stateStore.saveMediaLibraryRecord(record, for: item)
        }
        updateMetadataForSelection()
        showHUD(watched ? "Marked watched" : "Marked unwatched")
    }

    @objc func setTagsForSelectedItem(_ sender: Any? = nil) {
        guard let item = selectedOrCurrentItem else {
            showHUD("Select a playlist item first")
            return
        }

        let record = stateStore.mediaLibraryRecord(for: item)
        let alert = NSAlert()
        alert.messageText = "Set Tags"
        alert.informativeText = "Enter comma-separated tags for \(item.title)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.stringValue = record.tags.joined(separator: ", ")
        input.setAccessibilityLabel("Media tags")
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var updatedRecord = record
        updatedRecord.tags = LibraryCatalog.normalizedTags(from: input.stringValue)
        updatedRecord.updatedAt = Date()
        stateStore.saveMediaLibraryRecord(updatedRecord, for: item)
        updateMetadataForSelection()
        showHUD("Tags updated")
    }

    @objc func importEnterpriseLicense(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Import Enterprise License"
        panel.message = "Choose a signed Video Player enterprise license JSON file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try EnterpriseLicenseManager.installLicense(from: url)
            AppLogger.info("Enterprise license installed from \(url.lastPathComponent)", flush: true)
            showHUD("License installed")
            showLicenseStatus(sender)
        } catch {
            AppLogger.error("Enterprise license import failed error=\(error.localizedDescription)", flush: true)
            showTextDialog(
                title: "License Import Failed",
                text: error.localizedDescription,
                height: 120
            )
        }
    }

    @objc func exportSupportBundle(_ sender: Any? = nil) {
        let policy = EnterprisePolicy.snapshot()
        let includeLogs = shouldIncludeLogsInSupportBundle(policy: policy)
        if includeLogs == nil {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Export Support Bundle"
        panel.message = "Choose a folder where Video Player should create the support bundle."
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        showHUD("Exporting support bundle")
        let selectedItem = selectedOrCurrentItem

        Task { [weak self] in
            guard let self else { return }
            let report = await self.currentPlaybackDiagnosticReport().text
            let request = SupportBundleRequest(
                destinationDirectory: destination,
                diagnosticReport: report,
                policy: policy,
                licenseStatus: EnterpriseLicenseManager.status(),
                selectedItem: selectedItem,
                includeLogs: includeLogs == true,
                redactPaths: policy.redactSupportBundlePaths,
                now: Date()
            )

            do {
                let bundleURL = try SupportBundleExporter.export(request: request)
                await MainActor.run {
                    AppLogger.info("Support bundle exported path=\(bundleURL.path)", flush: true)
                    NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                    self.showHUD("Support bundle exported")
                }
                if let uploadURL = policy.supportUploadURL {
                    await self.offerSupportBundleUpload(bundleURL: bundleURL, endpoint: uploadURL)
                }
            } catch {
                await MainActor.run {
                    AppLogger.error("Support bundle export failed error=\(error.localizedDescription)", flush: true)
                    self.showTextDialog(title: "Support Bundle Failed", text: error.localizedDescription, height: 120)
                }
            }
        }
    }

    @MainActor
    private func offerSupportBundleUpload(bundleURL: URL, endpoint: URL) async {
        let alert = NSAlert()
        alert.messageText = "Upload Support Bundle?"
        alert.informativeText = "Your organization configured a support upload endpoint:\n\(endpoint.absoluteString)"
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Skip")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        showHUD("Uploading support bundle")
        do {
            let result = try await SupportBundleUploader.upload(bundleDirectory: bundleURL, endpoint: endpoint)
            if result.succeeded {
                showHUD("Support bundle uploaded")
            } else {
                showTextDialog(
                    title: "Upload Failed",
                    text: "Server returned HTTP \(result.statusCode).\n\n\(result.responseText)",
                    height: 180
                )
            }
        } catch {
            showTextDialog(title: "Upload Failed", text: error.localizedDescription, height: 160)
        }
    }

    @objc func toggleMiniPlayer(_ sender: Any? = nil) {
        guard let window = view.window else { return }
        if isMiniPlayer {
            if let savedWindowFrame {
                window.setFrame(savedWindowFrame, display: true, animate: true)
            }
            window.level = savedWindowLevel
            isMiniPlayer = false
            showHUD("Mini player off")
        } else {
            savedWindowFrame = window.frame
            savedWindowLevel = window.level
            window.level = .floating
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            let size = NSSize(width: 520, height: 320)
            let origin = NSPoint(x: screenFrame.maxX - size.width - 24, y: screenFrame.minY + 24)
            window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
            if sidebarView?.isHidden == false {
                toggleSidebar(nil)
            }
            isMiniPlayer = true
            showHUD("Mini player")
        }
    }

    @objc func toggleTheaterMode(_ sender: Any? = nil) {
        isTheaterMode.toggle()
        if isTheaterMode, sidebarView?.isHidden == false {
            toggleSidebar(nil)
        }
        showHUD(isTheaterMode ? "Theater mode" : "Theater mode off")
    }

    @objc func togglePictureInPicture(_ sender: Any? = nil) {
        toggleMiniPlayer(sender)
        showHUD("Floating player")
    }

    @objc func takeScreenshot(_ sender: Any? = nil) {
        guard currentItem != nil else {
            showHUD("No video frame")
            return
        }

        do {
            let url = try nextScreenshotURL()
            switch currentEngine {
            case .vlc:
                if vlcBridge.takeSnapshot(to: url) {
                    showHUD("Screenshot saved")
                } else {
                    showHUD("Screenshot failed")
                }
            case .native:
                try takeNativeScreenshot(to: url)
                showHUD("Screenshot saved")
            case .mpv, .none:
                showHUD("Screenshot unavailable")
            }
        } catch {
            showHUD("Screenshot failed")
        }
    }

    @objc func setLoopStart(_ sender: Any? = nil) {
        loopStart = currentPlaybackTime()
        showHUD("Loop A \(formatTime(loopStart ?? 0))")
    }

    @objc func setLoopEnd(_ sender: Any? = nil) {
        loopEnd = currentPlaybackTime()
        if let loopStart, let loopEnd, loopEnd <= loopStart {
            self.loopEnd = nil
            showHUD("Loop B must be after A")
        } else {
            showHUD("Loop B \(formatTime(loopEnd ?? 0))")
        }
    }

    @objc func clearLoop(_ sender: Any? = nil) {
        loopStart = nil
        loopEnd = nil
        showHUD("Loop cleared")
    }

    func applyAudioPreset(named name: String) {
        guard let preset = AudioPreset(rawValue: name) else { return }
        applyAudioPreset(preset)
    }

    func chapterItems() -> [ChapterOption] {
        guard currentEngine == .vlc else { return [] }
        return vlcBridge.chapters()
    }

    func selectChapter(at index: Int) {
        let chapters = chapterItems()
        guard chapters.indices.contains(index) else { return }
        if vlcBridge.selectChapter(index: chapters[index].index) {
            showHUD(chapters[index].name)
        }
    }

    @objc func previousChapter(_ sender: Any? = nil) {
        guard currentEngine == .vlc else {
            showHUD("Chapters need VLC playback")
            return
        }
        vlcBridge.previousChapter()
        showHUD("Previous chapter")
    }

    @objc func nextChapter(_ sender: Any? = nil) {
        guard currentEngine == .vlc else {
            showHUD("Chapters need VLC playback")
            return
        }
        vlcBridge.nextChapter()
        showHUD("Next chapter")
    }

    func audioOutputDevices() -> [AudioOutputDevice] {
        guard currentEngine == .vlc else { return [] }
        return vlcBridge.audioOutputDevices()
    }

    func selectAudioOutputDevice(id: String, name: String) {
        if vlcBridge.selectAudioOutputDevice(id: id) {
            showHUD("Audio output: \(name)")
        }
    }

    @objc func decreaseAudioDelay(_ sender: Any? = nil) {
        adjustAudioDelay(by: -0.1)
    }

    @objc func increaseAudioDelay(_ sender: Any? = nil) {
        adjustAudioDelay(by: 0.1)
    }

    @objc func resetAudioDelay(_ sender: Any? = nil) {
        setAudioDelay(0)
    }

    @objc func showVideoAdjustments(_ sender: Any? = nil) {
        if let videoAdjustmentPanel {
            videoAdjustmentPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 292),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Video Adjustments"
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        videoAdjustmentSliders = [:]
        for key in VideoAdjustmentKey.allCases {
            stack.addArrangedSubview(makeVideoAdjustmentRow(for: key))
        }

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetVideoAdjustments(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.toolTip = "Reset video adjustments"
        resetButton.setAccessibilityLabel("Reset video adjustments")
        resetButton.setAccessibilityHelp("Return brightness, contrast, saturation, hue, and gamma to their default values.")
        let buttonRow = NSStackView(views: [NSView(), resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        stack.addArrangedSubview(buttonRow)

        let contentView = NSView()
        contentView.addSubview(stack)
        panel.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        videoAdjustmentPanel = panel
        view.window?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func resetVideoAdjustments(_ sender: Any? = nil) {
        currentVideoAdjustments = VideoAdjustments()
        for key in VideoAdjustmentKey.allCases {
            videoAdjustmentSliders[key]?.doubleValue = key.defaultValue
        }
        applyVideoAdjustments(showHUD: true)
    }

    @objc func togglePlayPause(_ sender: Any?) {
        switch currentEngine {
        case .native:
            if avPlayer.timeControlStatus == .playing {
                avPlayer.pause()
                showHUD("Paused")
            } else {
                avPlayer.play()
                showHUD("Play")
            }
        case .vlc:
            vlcBridge.togglePlayPause()
            showHUD(vlcBridge.isPlaying ? "Paused" : "Play")
        case .mpv:
            mpvBridge.togglePlayPause()
            showHUD("Play/Pause")
        case .none:
            if playlist.isEmpty {
                openFilesPanel(replacePlaylist: true)
            } else {
                playItem(at: currentIndex ?? 0)
            }
        }
        refreshControls()
    }

    @objc func seekBackward(_ sender: Any?) {
        seek(relativeSeconds: -10)
    }

    @objc func seekForward(_ sender: Any?) {
        seek(relativeSeconds: 10)
    }

    @objc func playPrevious(_ sender: Any?) {
        guard !playlist.isEmpty else { return }
        let index = currentIndex ?? 0
        playItem(at: max(index - 1, 0))
    }

    @objc func playNext(_ sender: Any?) {
        guard !playlist.isEmpty else { return }
        let index = currentIndex ?? -1
        playItem(at: min(index + 1, playlist.count - 1))
    }

    @objc func volumeUp(_ sender: Any?) {
        adjustVolume(by: 5)
    }

    @objc func volumeDown(_ sender: Any?) {
        adjustVolume(by: -5)
    }

    @objc func toggleMute(_ sender: Any?) {
        if isMuted {
            setVolume(volumeBeforeMute, showHUD: true)
        } else {
            volumeBeforeMute = volumeSlider.doubleValue
            setVolume(0, showHUD: true)
        }
        isMuted.toggle()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard let sidebarView else { return }
        let shouldHide = !sidebarView.isHidden

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            sidebarWidthConstraint?.animator().constant = shouldHide ? 0 : 280
            sidebarView.animator().isHidden = shouldHide
            splitView?.animator().layoutSubtreeIfNeeded()
        }

        updateSidebarButton(sidebarHidden: shouldHide)
        showHUD(shouldHide ? "Sidebar hidden" : "Sidebar shown")
    }

    @objc private func openFromToolbar(_ sender: Any?) {
        openFilesPanel(replacePlaylist: playlist.isEmpty)
    }

    @objc private func clearPlaylist(_ sender: Any?) {
        guard confirmClearPlaylist() else { return }
        stopPlayback()
        playlist.removeAll()
        currentIndex = nil
        loopStart = nil
        loopEnd = nil
        clearPlaylistFilter()
        tableView.reloadData()
        updateEmptyState()
        refreshPlaylistActionStates()
        updateNowPlaying(title: "Ready", detail: "")
        metadataRequestID += 1
        metadataTextView.stringValue = "Select a media item to inspect it before playback."
        savePlaylistState()
        showHUD("Playlist cleared")
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let seconds = sender.doubleValue
        currentTimeLabel.stringValue = formatTime(seconds)

        switch currentEngine {
        case .native:
            avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .vlc:
            vlcBridge.setTime(seconds)
        case .mpv:
            mpvBridge.setTime(seconds)
        case .none:
            break
        }
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        setVolume(sender.doubleValue, showHUD: true)
    }

    @objc private func speedChanged(_ sender: NSPopUpButton) {
        let speed = playbackRateFromSelection()
        if currentEngine == .native, avPlayer.rate > 0 {
            avPlayer.rate = Float(speed)
        }
        vlcBridge.setSpeed(speed)
        mpvBridge.setSpeed(speed)
        stateStore.saveSpeedTitle(sender.selectedItem?.title ?? "1x")
        showHUD("Speed \(sender.selectedItem?.title ?? "1x")")
    }

    @objc private func audioTrackChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingTrackMenus, let id = selectedTrackID(from: sender) else { return }
        if vlcBridge.selectAudioTrack(id: id) {
            showHUD("Audio: \(sender.selectedItem?.title ?? "Track")")
        }
    }

    @objc private func audioPresetChanged(_ sender: NSPopUpButton) {
        applyAudioPreset(named: sender.selectedItem?.title ?? AudioPreset.flat.rawValue)
    }

    @objc private func subtitleTrackChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingTrackMenus, let id = selectedTrackID(from: sender) else { return }
        if vlcBridge.selectSubtitleTrack(id: id) {
            showHUD("Subtitles: \(sender.selectedItem?.title ?? "Track")")
        }
    }

    @objc private func subtitleDelayChanged(_ sender: NSStepper) {
        let delay = sender.doubleValue
        subtitleDelayLabel.stringValue = String(format: "%.1fs", delay)
        guard currentEngine == .vlc else { return }
        if vlcBridge.setSubtitleDelay(seconds: delay) {
            showHUD("Subtitle delay \(String(format: "%.1fs", delay))")
        }
    }

    @objc private func audioDelayChanged(_ sender: NSStepper) {
        setAudioDelay(sender.doubleValue)
    }

    @objc private func videoAdjustmentSliderChanged(_ sender: NSSlider) {
        guard let identifier = sender.identifier?.rawValue,
              let key = VideoAdjustmentKey(rawValue: identifier)
        else {
            return
        }

        switch key {
        case .brightness:
            currentVideoAdjustments.brightness = sender.doubleValue
        case .contrast:
            currentVideoAdjustments.contrast = sender.doubleValue
        case .saturation:
            currentVideoAdjustments.saturation = sender.doubleValue
        case .hue:
            currentVideoAdjustments.hue = sender.doubleValue
        case .gamma:
            currentVideoAdjustments.gamma = sender.doubleValue
        }

        applyVideoAdjustments(showHUD: false)
    }

    @objc private func playlistSearchChanged(_ sender: NSSearchField) {
        playlistFilter = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        tableView.reloadData()
        restoreVisiblePlaylistSelection()
        updateMetadataForSelection()
        refreshPlaylistActionStates()
    }

    @objc private func playlistSortChanged(_ sender: NSPopUpButton) {
        playlistSortMode = PlaylistSortMode(title: sender.selectedItem?.title) ?? .currentOrder
        sortPlaylistPreservingCurrentItem()
        tableView.reloadData()
        restoreVisiblePlaylistSelection()
        updateMetadataForSelection()
        refreshPlaylistActionStates()
        stateStore.savePlaylistSortMode(playlistSortMode.rawValue)
        savePlaylistState()
        showHUD("Sorted by \(playlistSortMode.shortTitle)")
    }

    private func buildInterface(in rootView: NSView) {
        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        self.splitView = splitView
        rootView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        let sidebar = makeSidebar()
        let playerArea = makePlayerArea()
        sidebarView = sidebar
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(playerArea)
        let widthConstraint = sidebar.widthAnchor.constraint(equalToConstant: 280)
        widthConstraint.isActive = true
        sidebarWidthConstraint = widthConstraint
    }

    private func makeSidebar() -> NSView {
        let container = NSVisualEffectView()
        container.material = .sidebar
        container.blendingMode = .behindWindow

        let header = NSStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let title = NSTextField(labelWithString: "Playlist")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let openButton = iconButton(systemName: "plus", description: "Add media", action: #selector(openFromToolbar(_:)))
        let removeButton = iconButton(systemName: "minus", description: "Remove selected from playlist", action: #selector(removeSelectedPlaylistItems(_:)))
        let clearButton = iconButton(systemName: "trash", description: "Clear playlist", action: #selector(clearPlaylist(_:)))
        let hideSidebarButton = iconButton(systemName: "sidebar.left", description: "Hide sidebar", action: #selector(toggleSidebar(_:)))
        removePlaylistButton = removeButton
        clearPlaylistButton = clearButton

        header.addArrangedSubview(title)
        header.addArrangedSubview(openButton)
        header.addArrangedSubview(removeButton)
        header.addArrangedSubview(clearButton)
        header.addArrangedSubview(hideSidebarButton)

        playlistSearchField.translatesAutoresizingMaskIntoConstraints = false
        playlistSearchField.placeholderString = "Search playlist"
        playlistSearchField.sendsWholeSearchString = false
        playlistSearchField.sendsSearchStringImmediately = true
        playlistSearchField.target = self
        playlistSearchField.action = #selector(playlistSearchChanged(_:))
        playlistSearchField.setAccessibilityLabel("Search playlist")
        playlistSearchField.setAccessibilityHelp("Filter the playlist by title, extension, path, or stream URL.")

        playlistSortPopup.translatesAutoresizingMaskIntoConstraints = false
        playlistSortPopup.addItems(withTitles: PlaylistSortMode.allCases.map(\.title))
        playlistSortPopup.selectItem(withTitle: playlistSortMode.title)
        playlistSortPopup.target = self
        playlistSortPopup.action = #selector(playlistSortChanged(_:))
        playlistSortPopup.toolTip = "Sort playlist"
        playlistSortPopup.setAccessibilityLabel("Sort playlist")
        playlistSortPopup.setAccessibilityHelp("Sort the playlist by current order, title, media type, or location.")

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 54
        tableView.style = .sourceList
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        tableView.registerForDraggedTypes([.videoPlayerPlaylistRows])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setAccessibilityLabel("Playlist")
        tableView.setAccessibilityHelp("Select media items to inspect, remove, or drag reorder; double-click to start playback.")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("media"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let metadataPanel = NSVisualEffectView()
        metadataPanel.translatesAutoresizingMaskIntoConstraints = false
        metadataPanel.material = .underWindowBackground
        metadataPanel.blendingMode = .withinWindow

        let metadataTitle = NSTextField(labelWithString: "Inspector")
        metadataTitle.translatesAutoresizingMaskIntoConstraints = false
        metadataTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        metadataTextView.translatesAutoresizingMaskIntoConstraints = false
        metadataTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        metadataTextView.textColor = .secondaryLabelColor
        metadataTextView.maximumNumberOfLines = 18
        metadataTextView.lineBreakMode = .byTruncatingMiddle
        metadataTextView.setAccessibilityLabel("Media inspector")
        metadataTextView.setAccessibilityHelp("Shows metadata for the selected media before playback.")

        metadataPanel.addSubview(metadataTitle)
        metadataPanel.addSubview(metadataTextView)

        container.addSubview(header)
        container.addSubview(playlistSearchField)
        container.addSubview(playlistSortPopup)
        container.addSubview(scrollView)
        container.addSubview(metadataPanel)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),

            playlistSearchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            playlistSearchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            playlistSearchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),

            playlistSortPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            playlistSortPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            playlistSortPopup.topAnchor.constraint(equalTo: playlistSearchField.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: playlistSortPopup.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: metadataPanel.topAnchor),

            metadataPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            metadataPanel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            metadataPanel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            metadataPanel.heightAnchor.constraint(equalToConstant: 260),

            metadataTitle.leadingAnchor.constraint(equalTo: metadataPanel.leadingAnchor, constant: 14),
            metadataTitle.trailingAnchor.constraint(equalTo: metadataPanel.trailingAnchor, constant: -14),
            metadataTitle.topAnchor.constraint(equalTo: metadataPanel.topAnchor, constant: 12),

            metadataTextView.leadingAnchor.constraint(equalTo: metadataPanel.leadingAnchor, constant: 14),
            metadataTextView.trailingAnchor.constraint(equalTo: metadataPanel.trailingAnchor, constant: -14),
            metadataTextView.topAnchor.constraint(equalTo: metadataTitle.bottomAnchor, constant: 8),
            metadataTextView.bottomAnchor.constraint(lessThanOrEqualTo: metadataPanel.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makePlayerArea() -> NSView {
        let container = NSView()
        playerAreaView = container
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.player = avPlayer
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        playerView.setAccessibilityLabel("Video player")

        vlcVideoSurface.translatesAutoresizingMaskIntoConstraints = false
        vlcVideoSurface.wantsLayer = true
        vlcVideoSurface.layer?.backgroundColor = NSColor.black.cgColor
        vlcVideoSurface.isHidden = true
        vlcVideoSurface.setAccessibilityLabel("Video playback surface")

        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.orientation = .vertical
        emptyStateContainer.alignment = .centerX
        emptyStateContainer.spacing = 12
        emptyStateContainer.setAccessibilityLabel("Empty player state")

        emptyStateLabel.font = .systemFont(ofSize: 21, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.setAccessibilityLabel("Drop media files here")

        emptyStateSubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        emptyStateSubtitleLabel.textColor = .tertiaryLabelColor
        emptyStateSubtitleLabel.alignment = .center
        emptyStateSubtitleLabel.maximumNumberOfLines = 2
        emptyStateSubtitleLabel.lineBreakMode = .byWordWrapping
        emptyStateSubtitleLabel.setAccessibilityLabel("Open a local file, add a folder, or paste a public stream URL.")

        configureEmptyStateButton(emptyStateOpenButton, action: #selector(openFromToolbar(_:)))
        configureEmptyStateButton(emptyStateStreamButton, action: #selector(openNetworkStreamDialog(_:)))
        let emptyStateActions = NSStackView(views: [emptyStateOpenButton, emptyStateStreamButton])
        emptyStateActions.orientation = .horizontal
        emptyStateActions.alignment = .centerY
        emptyStateActions.spacing = 10

        emptyStateContainer.addArrangedSubview(emptyStateLabel)
        emptyStateContainer.addArrangedSubview(emptyStateSubtitleLabel)
        emptyStateContainer.addArrangedSubview(emptyStateActions)

        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.alignment = .center
        hudLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        hudLabel.textColor = .white
        hudLabel.isBezeled = false
        hudLabel.isEditable = false
        hudLabel.drawsBackground = true
        hudLabel.backgroundColor = NSColor.black.withAlphaComponent(0.68)
        hudLabel.maximumNumberOfLines = 1
        hudLabel.isHidden = true
        hudLabel.wantsLayer = true
        hudLabel.layer?.cornerRadius = 8
        hudLabel.layer?.masksToBounds = true
        hudLabel.setAccessibilityLabel("Playback status")

        let controls = makeControls()
        controls.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(playerView)
        container.addSubview(vlcVideoSurface)
        container.addSubview(emptyStateContainer)
        container.addSubview(hudLabel)
        container.addSubview(controls)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: controls.topAnchor),

            vlcVideoSurface.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            vlcVideoSurface.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            vlcVideoSurface.topAnchor.constraint(equalTo: playerView.topAnchor),
            vlcVideoSurface.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),

            emptyStateContainer.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            emptyStateContainer.leadingAnchor.constraint(greaterThanOrEqualTo: playerView.leadingAnchor, constant: 24),
            emptyStateContainer.trailingAnchor.constraint(lessThanOrEqualTo: playerView.trailingAnchor, constant: -24),

            hudLabel.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            hudLabel.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            hudLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            hudLabel.widthAnchor.constraint(lessThanOrEqualTo: playerView.widthAnchor, multiplier: 0.75),
            hudLabel.heightAnchor.constraint(equalToConstant: 54),

            controls.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeControls() -> NSView {
        let controls = NSView()
        controls.wantsLayer = true
        controls.appearance = NSAppearance(named: .darkAqua)
        controls.layer?.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 0.98).cgColor
        controls.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        controls.layer?.borderWidth = 1

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 16, right: 18)

        seekSlider.target = self
        seekSlider.action = #selector(sliderChanged(_:))
        seekSlider.isContinuous = true
        seekSlider.sendAction(on: [.leftMouseDragged, .leftMouseUp])
        seekSlider.setAccessibilityLabel("Playback position")
        seekSlider.setAccessibilityHelp("Drag to seek through the current media.")

        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        currentTimeLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        durationLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        currentTimeLabel.alignment = .right
        durationLabel.alignment = .left
        currentTimeLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        durationLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let timeline = NSStackView(views: [currentTimeLabel, seekSlider, durationLabel])
        timeline.orientation = .horizontal
        timeline.alignment = .centerY
        timeline.spacing = 10

        let previousButton = iconButton(systemName: "backward.end.fill", description: "Previous", action: #selector(playPrevious(_:)), controlBarStyle: true)
        let backButton = iconButton(systemName: "gobackward.10", description: "Back 10 seconds", action: #selector(seekBackward(_:)), controlBarStyle: true)
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playPauseButton.bezelStyle = .texturedRounded
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause(_:))
        playPauseButton.toolTip = "Play or pause"
        playPauseButton.setAccessibilityLabel("Play")
        playPauseButton.setAccessibilityHelp("Start or pause playback.")
        playPauseButton.contentTintColor = .white
        playPauseButton.appearance = NSAppearance(named: .darkAqua)
        playPauseButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        playPauseButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let forwardButton = iconButton(systemName: "goforward.10", description: "Forward 10 seconds", action: #selector(seekForward(_:)), controlBarStyle: true)
        let nextButton = iconButton(systemName: "forward.end.fill", description: "Next", action: #selector(playNext(_:)), controlBarStyle: true)
        sidebarButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")
        sidebarButton.bezelStyle = .texturedRounded
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar(_:))
        sidebarButton.toolTip = "Hide sidebar"
        sidebarButton.setAccessibilityLabel("Hide sidebar")
        sidebarButton.setAccessibilityHelp("Show or hide the playlist and inspector sidebar.")
        sidebarButton.contentTintColor = .white
        sidebarButton.appearance = NSAppearance(named: .darkAqua)
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        sidebarButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        speedPopup.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speedPopup.selectItem(withTitle: "1x")
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged(_:))
        speedPopup.toolTip = "Playback speed"
        speedPopup.setAccessibilityLabel("Playback speed")
        speedPopup.setAccessibilityHelp("Choose a playback speed.")
        speedPopup.widthAnchor.constraint(equalToConstant: 78).isActive = true

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        volumeSlider.toolTip = "Volume boost"
        volumeSlider.setAccessibilityLabel("Volume")
        volumeSlider.setAccessibilityHelp("Adjust volume from 0 to 200 percent.")
        volumeSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        volumeSlider.doubleValue = defaultVolume
        setVolume(defaultVolume, persist: false)

        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        volumeLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        volumeLabel.alignment = .right
        volumeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let volumeIcon = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume") ?? NSImage())
        volumeIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        volumeIcon.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        volumeIcon.setAccessibilityLabel("Volume")

        let flexibleGap = NSView()
        flexibleGap.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let fullscreenButton = iconButton(systemName: "arrow.up.left.and.arrow.down.right", description: "Full screen", action: #selector(toggleFullscreen(_:)), controlBarStyle: true)

        let transport = NSStackView(views: [
            previousButton,
            backButton,
            playPauseButton,
            forwardButton,
            nextButton,
            flexibleGap,
            speedPopup,
            volumeIcon,
            volumeSlider,
            volumeLabel,
            sidebarButton,
            fullscreenButton
        ])
        transport.orientation = .horizontal
        transport.alignment = .centerY
        transport.spacing = 10

        let trackControls = makeTrackControls()

        stack.addArrangedSubview(timeline)
        stack.addArrangedSubview(transport)
        stack.addArrangedSubview(trackControls)
        controls.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controls.topAnchor),
            stack.bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])

        return controls
    }

    private func makeTrackControls() -> NSView {
        audioTrackPopup.target = self
        audioTrackPopup.action = #selector(audioTrackChanged(_:))
        audioTrackPopup.toolTip = "Audio track"
        audioTrackPopup.setAccessibilityLabel("Audio track")
        audioTrackPopup.setAccessibilityHelp("Choose an available audio track.")
        audioTrackPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        audioPresetPopup.addItems(withTitles: AudioPreset.allCases.map(\.rawValue))
        audioPresetPopup.selectItem(withTitle: currentAudioPreset.rawValue)
        audioPresetPopup.target = self
        audioPresetPopup.action = #selector(audioPresetChanged(_:))
        audioPresetPopup.toolTip = "Audio preset"
        audioPresetPopup.setAccessibilityLabel("Audio preset")
        audioPresetPopup.setAccessibilityHelp("Choose an audio equalizer preset.")
        audioPresetPopup.widthAnchor.constraint(equalToConstant: 132).isActive = true

        audioDelayStepper.minValue = -30
        audioDelayStepper.maxValue = 30
        audioDelayStepper.increment = 0.1
        audioDelayStepper.target = self
        audioDelayStepper.action = #selector(audioDelayChanged(_:))
        audioDelayStepper.toolTip = "Audio delay"
        audioDelayStepper.setAccessibilityLabel("Audio delay")
        audioDelayStepper.setAccessibilityHelp("Move audio earlier or later in 0.1 second increments.")
        audioDelayStepper.widthAnchor.constraint(equalToConstant: 52).isActive = true

        audioDelayLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        audioDelayLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        audioDelayLabel.alignment = .right
        audioDelayLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        audioDelayLabel.setAccessibilityLabel("Current audio delay")

        subtitleTrackPopup.target = self
        subtitleTrackPopup.action = #selector(subtitleTrackChanged(_:))
        subtitleTrackPopup.toolTip = "Subtitle track"
        subtitleTrackPopup.setAccessibilityLabel("Subtitle track")
        subtitleTrackPopup.setAccessibilityHelp("Choose an available subtitle track.")
        subtitleTrackPopup.widthAnchor.constraint(equalToConstant: 230).isActive = true

        subtitleDelayStepper.minValue = -30
        subtitleDelayStepper.maxValue = 30
        subtitleDelayStepper.increment = 0.1
        subtitleDelayStepper.target = self
        subtitleDelayStepper.action = #selector(subtitleDelayChanged(_:))
        subtitleDelayStepper.toolTip = "Subtitle delay"
        subtitleDelayStepper.setAccessibilityLabel("Subtitle delay")
        subtitleDelayStepper.setAccessibilityHelp("Move subtitles earlier or later in 0.1 second increments.")
        subtitleDelayStepper.widthAnchor.constraint(equalToConstant: 52).isActive = true

        subtitleDelayLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        subtitleDelayLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        subtitleDelayLabel.alignment = .right
        subtitleDelayLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        subtitleDelayLabel.setAccessibilityLabel("Current subtitle delay")

        let audioIcon = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio") ?? NSImage())
        audioIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        audioIcon.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        audioIcon.setAccessibilityLabel("Audio controls")
        let subtitleIcon = NSImageView(image: NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "Subtitles") ?? NSImage())
        subtitleIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        subtitleIcon.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        subtitleIcon.setAccessibilityLabel("Subtitle controls")
        let loadSubtitleButton = iconButton(systemName: "text.badge.plus", description: "Load subtitles", action: #selector(openSubtitlePanel(_:)), controlBarStyle: true)

        let audioGap = NSView()
        audioGap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let audioRow = NSStackView(views: [
            audioIcon,
            audioTrackPopup,
            audioPresetPopup,
            audioDelayStepper,
            audioDelayLabel,
            audioGap
        ])
        audioRow.orientation = .horizontal
        audioRow.alignment = .centerY
        audioRow.spacing = 8

        let subtitleGap = NSView()
        subtitleGap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let subtitleRow = NSStackView(views: [
            subtitleIcon,
            subtitleTrackPopup,
            loadSubtitleButton,
            subtitleDelayStepper,
            subtitleDelayLabel,
            subtitleGap
        ])
        subtitleRow.orientation = .horizontal
        subtitleRow.alignment = .centerY
        subtitleRow.spacing = 8

        let stack = NSStackView(views: [audioRow, subtitleRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        resetTrackMenus()
        return stack
    }

    private func configurePlayer() {
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.updateTimeline(currentTime: time)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerFailed(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
    }

    private func configureVLCEvents() {
        vlcBridge.eventHandler = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleVLCEvent(event)
            }
        }
    }

    private func configureScrollWheelVolume() {
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldUseScrollWheelForVolume(event) else {
                return event
            }

            let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
            guard abs(rawDelta) > 0.05 else { return nil }

            let multiplier = event.hasPreciseScrollingDeltas ? 0.35 : 5.0
            self.adjustVolume(by: rawDelta * multiplier)
            return nil
        }
    }

    private func configureKeyboardShortcuts() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyDown(event) else { return event }
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.window === view.window else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        if event.window?.firstResponder is NSTextView {
            return false
        }

        switch event.keyCode {
        case 51, 117:
            removeSelectedPlaylistItems(nil)
        case 49:
            togglePlayPause(nil)
        case 123:
            seekBackward(nil)
        case 124:
            seekForward(nil)
        case 125:
            volumeDown(nil)
        case 126:
            volumeUp(nil)
        default:
            let key = event.charactersIgnoringModifiers?.lowercased()
            switch key {
            case "j":
                seekBackward(nil)
            case "k":
                togglePlayPause(nil)
            case "l":
                seekForward(nil)
            case "m":
                toggleMute(nil)
            case "f":
                toggleFullscreen(nil)
            case "b":
                toggleSidebar(nil)
            case "[":
                playPrevious(nil)
            case "]":
                playNext(nil)
            default:
                return false
            }
        }

        return true
    }

    private func shouldUseScrollWheelForVolume(_ event: NSEvent) -> Bool {
        guard let playerAreaView, let window = playerAreaView.window, event.window === window else {
            return false
        }

        let location = playerAreaView.convert(event.locationInWindow, from: nil)
        return playerAreaView.bounds.contains(location)
    }

    private func addMedia(from urls: [URL], replacePlaylist: Bool, autoplay: Bool) {
        if urls.count == 1, let playlistURL = urls.first, isPlaylistFile(playlistURL) {
            showHUD("Importing playlist")
            Task { [weak self] in
                await self?.importPlaylist(from: playlistURL, replacePlaylist: replacePlaylist)
            }
            return
        }

        let subtitleURLs = urls.filter(isSubtitleFile)
        let items = urls
            .flatMap(mediaURLs(from:))
            .map(MediaItem.init(url:))

        guard !items.isEmpty else {
            if let subtitleURL = subtitleURLs.first {
                loadSubtitle(subtitleURL)
            } else {
                updateNowPlaying(title: "No supported media found", detail: "Try MP4, M4V, MOV, MKV, AVI, WebM, FLAC, MP3, WAV, or subtitle files.")
            }
            return
        }

        addMediaItems(items, replacePlaylist: replacePlaylist, autoplay: autoplay)

        if autoplay, let subtitleURL = subtitleURLs.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadSubtitle(subtitleURL)
            }
        }
    }

    private func addMediaItems(_ items: [MediaItem], replacePlaylist: Bool, autoplay: Bool) {
        let activeItem = currentItem
        if replacePlaylist {
            stopPlayback()
            playlist = items
            currentIndex = nil
        } else {
            playlist.append(contentsOf: items)
        }

        sortPlaylistPreserving(item: activeItem)
        let targetIndex = items.first.flatMap { playlist.firstIndex(of: $0) }
        clearPlaylistFilter()
        tableView.reloadData()
        updateEmptyState()
        refreshPlaylistActionStates()
        savePlaylistState()

        if currentIndex == nil, autoplay, let targetIndex {
            playItem(at: targetIndex)
        } else if currentIndex == nil, let targetIndex {
            selectItemForInspection(at: targetIndex)
        }
    }

    private func mediaURLs(from url: URL) -> [URL] {
        guard url.isFileURL else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        if isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            var mediaURLs: [URL] = []
            var enumeratedItemCount = 0
            var wasLimited = false

            while let item = enumerator.nextObject() {
                enumeratedItemCount += 1
                if enumeratedItemCount > maximumEnumeratedFolderItems || mediaURLs.count >= maximumScannedMediaFiles {
                    wasLimited = true
                    break
                }
                guard let fileURL = item as? URL else { continue }
                if isSupportedMedia(fileURL) {
                    mediaURLs.append(fileURL)
                }
            }

            if wasLimited {
                showHUD("Folder scan limited to \(mediaURLs.count) media files")
            }

            return mediaURLs.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }

        return isSupportedMedia(url) ? [url] : []
    }

    private func isSupportedMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    private func isSubtitleFile(_ url: URL) -> Bool {
        url.isFileURL && subtitleExtensions.contains(url.pathExtension.lowercased())
    }

    private func isPlaylistFile(_ url: URL) -> Bool {
        url.isFileURL && ["m3u", "m3u8"].contains(url.pathExtension.lowercased())
    }

    private func playItem(at index: Int) {
        saveCurrentPosition()
        guard playlist.indices.contains(index) else { return }
        playbackRequestID += 1
        let requestID = playbackRequestID
        nativePlaybackInspectionTask?.cancel()
        currentIndex = index
        savePlaylistState()
        restoreVisiblePlaylistSelection()

        let item = playlist[index]
        AppLogger.info("Playback requested requestID=\(requestID) title=\(item.title) url=\(item.url.absoluteString)", flush: true)
        stateStore.addRecentMedia(item)
        updateMetadata(for: item)
        updateNowPlaying(title: item.title, detail: item.subtitle)
        let resumeTime = promptedResumeTime(for: item)

        if item.isNetworkStream {
            showHUD("Checking stream")
            Task { [weak self] in
                await self?.startNetworkPlaybackAfterValidation(item, at: index, resumeTime: resumeTime)
            }
            refreshControls()
            return
        }

        startLocalPlaybackAfterInspection(item, at: index, resumeTime: resumeTime, requestID: requestID)
    }

    @MainActor
    private func startNetworkPlaybackAfterValidation(_ item: MediaItem, at index: Int, resumeTime: Double?) async {
        let stream = await NetworkStreamValidator.validatedStream(
            from: item.url.absoluteString,
            allowPrivateNetworkHosts: stateStore.privateNetworkStreamsEnabled()
        )

        guard playlist.indices.contains(index),
              playlist[index] == item,
              currentIndex == index
        else {
            return
        }

        guard let stream else {
            currentEngine = .none
            engineLabel.stringValue = "Stream blocked because its URL, DNS result, or private-network status is no longer trusted."
            showHUD("Stream blocked")
            refreshControls()
            return
        }

        guard !networkStreamResolutionChanged(stream) else {
            currentEngine = .none
            engineLabel.stringValue = "Stream blocked because its DNS result changed since it was added."
            showHUD("Stream DNS changed")
            refreshControls()
            return
        }

        rememberValidatedNetworkStream(stream)
        startPlayback(item, resumeTime: resumeTime)
        refreshControls()
    }

    private func startLocalPlaybackAfterInspection(
        _ item: MediaItem,
        at index: Int,
        resumeTime: Double?,
        requestID: Int
    ) {
        let nativePlaybackExtensions = self.nativeExtensions

        nativePlaybackInspectionTask = Task { [weak self] in
            AppLogger.info("Native playback inspection started requestID=\(requestID) title=\(item.title)", flush: true)
            let assessment = await NativePlaybackPolicy.assessment(
                for: item,
                nativeExtensions: nativePlaybackExtensions
            )
            AppLogger.info("Native playback inspection finished requestID=\(requestID) routing=\(assessment.routing) codecs=\(assessment.detectedVideoCodecs.sorted().joined(separator: ",")) reason=\(assessment.reason ?? "none")", flush: true)

            await MainActor.run {
                guard let self,
                      self.playbackRequestID == requestID,
                      self.currentIndex == index,
                      self.playlist.indices.contains(index),
                      self.playlist[index] == item
                else {
                    return
                }

                self.startPlayback(item, resumeTime: resumeTime, nativeAssessment: assessment)
                self.refreshControls()
            }
        }
    }

    private func startPlayback(
        _ item: MediaItem,
        resumeTime: Double?,
        nativeAssessment: NativePlaybackAssessment = .native
    ) {
        AppLogger.info("Start playback routing title=\(item.title) routing=\(nativeAssessment.routing) externalAvailable=\(AppSecurityPolicy.externalMediaEnginesAvailable) externalEnabled=\(stateStore.externalMediaEnginesEnabled())", flush: true)
        if nativeAssessment.requiresExternalEngine,
           promptToEnableExternalEnginesIfNeeded(for: item, resumeTime: resumeTime, assessment: nativeAssessment) {
            return
        }

        if shouldUseVLC(for: item, nativeAssessment: nativeAssessment) {
            playWithVLC(item, resumeTime: resumeTime)
        } else if shouldUseMPV(for: item, nativeAssessment: nativeAssessment) {
            playWithMPV(item, resumeTime: resumeTime)
        } else if nativeAssessment.requiresExternalEngine {
            handleUnsupportedNativePlayback(for: item, assessment: nativeAssessment)
        } else {
            playNatively(
                item,
                fallbackToMPV: true,
                resumeTime: resumeTime,
                nativeAssessment: nativeAssessment
            )
        }
    }

    private func promptToEnableExternalEnginesIfNeeded(
        for item: MediaItem,
        resumeTime: Double?,
        assessment: NativePlaybackAssessment
    ) -> Bool {
        guard AppSecurityPolicy.externalMediaEnginesAvailable,
              !stateStore.externalMediaEnginesEnabled()
        else {
            return false
        }

        AppLogger.info("Prompting user to enable external engines for title=\(item.title) reason=\(assessment.reason ?? "none")", flush: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable trusted VLC/mpv playback?"
        alert.informativeText = """
        \(assessment.reason ?? "This file needs a broader video codec engine.")

        Video Player will only use separately installed media engines that pass code-signature, Team ID, and Gatekeeper checks.
        """
        alert.addButton(withTitle: "Enable and Play")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            stateStore.setExternalMediaEnginesEnabled(true)
            AppLogger.info("User enabled external engines from playback prompt for title=\(item.title)", flush: true)
            showHUD("External engines enabled")
            startPlayback(item, resumeTime: resumeTime, nativeAssessment: assessment)
        } else {
            AppLogger.info("User canceled external-engine playback prompt for title=\(item.title)", flush: true)
            handleUnsupportedNativePlayback(for: item, assessment: assessment)
        }

        return true
    }

    private func playNatively(
        _ item: MediaItem,
        fallbackToMPV: Bool,
        resumeTime: Double?,
        nativeAssessment: NativePlaybackAssessment
    ) {
        AppLogger.info("Starting native AVFoundation playback title=\(item.title) reason=\(nativeAssessment.reason ?? "native")", flush: true)
        codecTimer?.invalidate()
        nativeVideoWatchdogTask?.cancel()
        vlcBridge.stop()
        mpvBridge.stop()
        currentEngine = .native
        seekSlider.isEnabled = true
        playerView.isHidden = false
        vlcVideoSurface.isHidden = true
        resetTrackMenus()

        let avItem = AVPlayerItem(url: item.url)
        itemStatusObservation = avItem.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            DispatchQueue.main.async {
                AppLogger.error("AVFoundation item failed title=\(item.title) error=\(observedItem.error?.localizedDescription ?? "unknown")", flush: true)
                self?.handleNativeFailure(for: item, fallbackToMPV: fallbackToMPV, error: observedItem.error)
            }
        }

        avPlayer.replaceCurrentItem(with: avItem)
        avPlayer.rate = Float(playbackRateFromSelection())
        if let resumeTime {
            avPlayer.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            showHUD("Resumed at \(formatTime(resumeTime))")
        }
        avPlayer.play()
        engineLabel.stringValue = nativeAssessment.reason ?? "Playing in-app with AVFoundation"
        scheduleNativeVideoWatchdog(for: item, requestID: playbackRequestID, fallbackToMPV: fallbackToMPV)
    }

    private func playWithVLC(_ item: MediaItem, resumeTime: Double?, fallbackToMPV: Bool = true) {
        AppLogger.info("Starting VLC playback title=\(item.title) fallbackToMPV=\(fallbackToMPV)", flush: true)
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        mpvBridge.stop()
        itemStatusObservation = nil
        codecTimer?.invalidate()
        nativeVideoWatchdogTask?.cancel()
        currentEngine = .vlc
        seekSlider.isEnabled = true
        playerView.isHidden = true
        vlcVideoSurface.isHidden = false
        resetTrackMenus()

        do {
            try vlcBridge.play(
                url: item.url,
                in: vlcVideoSurface,
                volume: volumeSlider.doubleValue,
                speed: playbackRateFromSelection()
            )
            engineLabel.stringValue = "Playing in-app with VLC codec engine"
            AppLogger.info("VLC playback started title=\(item.title)", flush: true)
            startCodecTimer()
            applyResumeTime(resumeTime)
            if currentAudioPreset != .flat {
                _ = vlcBridge.applyAudioPreset(currentAudioPreset)
            }
            if !currentVideoAdjustments.isDefault {
                _ = vlcBridge.applyVideoAdjustments(currentVideoAdjustments)
            }
            autoLoadSidecarSubtitle(for: item)
            scheduleTrackMenuRefresh()
        } catch {
            AppLogger.error("VLC playback failed title=\(item.title) error=\(error.localizedDescription)", flush: true)
            vlcBridge.stop()
            if fallbackToMPV, mpvBridge.isAvailable {
                AppLogger.info("Falling back from VLC to mpv title=\(item.title)", flush: true)
                playWithMPV(item, resumeTime: resumeTime)
                return
            }

            currentEngine = .none
            vlcVideoSurface.isHidden = true
            playerView.isHidden = false
            engineLabel.stringValue = error.localizedDescription
        }
    }

    private func playWithMPV(_ item: MediaItem, resumeTime: Double?) {
        AppLogger.info("Starting mpv playback title=\(item.title)", flush: true)
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        vlcBridge.stop()
        itemStatusObservation = nil
        codecTimer?.invalidate()
        nativeVideoWatchdogTask?.cancel()
        currentEngine = .mpv
        seekSlider.doubleValue = 0
        seekSlider.isEnabled = false
        currentTimeLabel.stringValue = "--:--"
        durationLabel.stringValue = "--:--"
        playerView.isHidden = true
        vlcVideoSurface.isHidden = true
        resetTrackMenus()

        do {
            try mpvBridge.play(
                url: item.url,
                volume: volumeSlider.doubleValue,
                speed: playbackRateFromSelection()
            ) { [weak self] in
                guard let self, self.currentEngine == .mpv else { return }
                AppLogger.info("mpv process exited title=\(item.title)", flush: true)
                self.currentEngine = .none
                self.refreshControls()
            }
            if let resumeTime {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.mpvBridge.setTime(resumeTime)
                }
                showHUD("Resumed at \(formatTime(resumeTime))")
            }
            engineLabel.stringValue = "Playing with mpv for broad codec support"
            AppLogger.info("mpv playback launched title=\(item.title)", flush: true)
        } catch {
            currentEngine = .none
            AppLogger.error("mpv playback failed title=\(item.title) error=\(error.localizedDescription)", flush: true)
            engineLabel.stringValue = error.localizedDescription
            playerView.isHidden = false
        }
    }

    private func shouldUseVLC(for _: MediaItem, nativeAssessment _: NativePlaybackAssessment) -> Bool {
        vlcBridge.isAvailable
    }

    private func shouldUseMPV(for item: MediaItem, nativeAssessment: NativePlaybackAssessment) -> Bool {
        (item.isNetworkStream || !nativeExtensions.contains(item.fileExtension) || nativeAssessment.prefersExternalEngine)
            && mpvBridge.isAvailable
    }

    private func handleUnsupportedNativePlayback(for item: MediaItem, assessment: NativePlaybackAssessment) {
        AppLogger.warning("Unsupported native playback title=\(item.title) reason=\(assessment.reason ?? "unknown")", flush: true)
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        vlcBridge.stop()
        mpvBridge.stop()
        itemStatusObservation = nil
        codecTimer?.invalidate()
        nativeVideoWatchdogTask?.cancel()
        currentEngine = .none
        seekSlider.isEnabled = false
        playerView.isHidden = false
        vlcVideoSurface.isHidden = true
        resetTrackMenus()

        let reason = assessment.reason ?? "This video codec is not available through Apple-native playback."
        engineLabel.stringValue = "\(reason) Enable a trusted VLC/mpv engine in an advanced build to play it."
        showHUD("Video codec needs VLC/mpv")
        refreshControls()
    }

    private func scheduleNativeVideoWatchdog(for item: MediaItem, requestID: Int, fallbackToMPV: Bool) {
        nativeVideoWatchdogTask?.cancel()
        AppLogger.debug("Scheduling native video watchdog requestID=\(requestID) title=\(item.title)")
        nativeVideoWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            let hasVideoTrack = await NativePlaybackPolicy.hasVideoTrack(item)

            await MainActor.run {
                guard let self,
                      self.playbackRequestID == requestID,
                      self.currentEngine == .native,
                      hasVideoTrack
                else {
                    return
                }

                let presentationSize = self.avPlayer.currentItem?.presentationSize ?? .zero
                guard presentationSize.width <= 1 || presentationSize.height <= 1 else {
                    AppLogger.debug("Native video watchdog passed requestID=\(requestID) title=\(item.title) presentationSize=\(presentationSize.width)x\(presentationSize.height)")
                    return
                }

                AppLogger.warning("Native video watchdog detected audio-only playback requestID=\(requestID) title=\(item.title)", flush: true)
                self.handleNativeAudioOnlyPlayback(for: item, fallbackToMPV: fallbackToMPV)
            }
        }
    }

    private func handleNativeAudioOnlyPlayback(for item: MediaItem, fallbackToMPV: Bool) {
        AppLogger.warning("Handling native audio-only playback title=\(item.title) fallbackToMPV=\(fallbackToMPV)", flush: true)
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        let assessment = NativePlaybackAssessment(
            routing: .requiresExternal,
            reason: "macOS started the audio track but did not produce a video frame. This file likely needs a trusted VLC/mpv engine for its video codec.",
            detectedVideoCodecs: []
        )

        if fallbackToMPV,
           promptToEnableExternalEnginesIfNeeded(for: item, resumeTime: nil, assessment: assessment) {
            return
        }

        handleNativeFailure(
            for: item,
            fallbackToMPV: fallbackToMPV,
            error: NativePlaybackError.audioOnlyVideo
        )
        showHUD("Video codec needs VLC/mpv")
    }

    private func handleNativeFailure(for item: MediaItem, fallbackToMPV: Bool, error: Error?) {
        AppLogger.error("Handling native playback failure title=\(item.title) fallbackToMPV=\(fallbackToMPV) error=\(error?.localizedDescription ?? "unknown")", flush: true)
        if fallbackToMPV, vlcBridge.isAvailable {
            playWithVLC(item, resumeTime: nil)
            return
        }

        if fallbackToMPV, mpvBridge.isAvailable {
            playWithMPV(item, resumeTime: nil)
            return
        }

        currentEngine = .none
        let message = error?.localizedDescription ?? "This file could not be opened by macOS."
        engineLabel.stringValue = "\(message) Install VLC or mpv separately for broader codec coverage and 200% volume boost."
        refreshControls()
    }

    private func stopPlayback() {
        saveCurrentPosition()
        playbackRequestID += 1
        nativePlaybackInspectionTask?.cancel()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        codecTimer?.invalidate()
        nativeVideoWatchdogTask?.cancel()
        vlcBridge.stop()
        mpvBridge.stop()
        currentEngine = .none
        itemStatusObservation = nil
        seekSlider.doubleValue = 0
        currentTimeLabel.stringValue = "0:00"
        durationLabel.stringValue = "0:00"
        resetTrackMenus()
        refreshControls()
    }

    private func seek(relativeSeconds seconds: Int) {
        switch currentEngine {
        case .native:
            let current = avPlayer.currentTime().seconds
            let target = max(current + Double(seconds), 0)
            avPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .vlc:
            vlcBridge.seek(seconds: seconds)
        case .mpv:
            mpvBridge.seek(seconds: seconds)
        case .none:
            return
        }

        showHUD(seconds > 0 ? "+\(seconds)s" : "\(seconds)s")
    }

    private func currentPlaybackTime() -> Double {
        switch currentEngine {
        case .native:
            avPlayer.currentTime().seconds
        case .vlc:
            vlcBridge.currentTime
        case .mpv, .none:
            0
        }
    }

    private func enforceLoopIfNeeded(_ currentSeconds: Double) {
        guard let loopStart, let loopEnd, loopEnd > loopStart, currentSeconds >= loopEnd else { return }
        switch currentEngine {
        case .native:
            avPlayer.seek(to: CMTime(seconds: loopStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .vlc:
            vlcBridge.setTime(loopStart)
        case .mpv:
            mpvBridge.setTime(loopStart)
        case .none:
            break
        }
    }

    private func playbackRateFromSelection() -> Double {
        let title = speedPopup.selectedItem?.title.replacingOccurrences(of: "x", with: "") ?? "1"
        return Double(title) ?? 1
    }

    private func adjustVolume(by delta: Double) {
        setVolume(volumeSlider.doubleValue + delta, showHUD: true)
    }

    private func setVolume(_ volume: Double, showHUD shouldShowHUD: Bool = false, persist: Bool = true) {
        let clampedVolume = min(max(volume, 0), maximumVolume)
        volumeSlider.doubleValue = clampedVolume
        volumeLabel.stringValue = "\(Int(clampedVolume.rounded()))%"

        avPlayer.volume = Float(min(clampedVolume, 100) / 100)
        vlcBridge.setVolume(clampedVolume)
        mpvBridge.setVolume(clampedVolume)

        if clampedVolume > 0 {
            isMuted = false
        }
        if persist {
            stateStore.saveVolume(clampedVolume)
        }
        if shouldShowHUD {
            showHUD("Volume \(Int(clampedVolume.rounded()))%")
        }
    }

    private func applyAudioPreset(_ preset: AudioPreset) {
        currentAudioPreset = preset
        stateStore.saveAudioPreset(preset.rawValue)
        audioPresetPopup.selectItem(withTitle: preset.rawValue)
        if currentEngine == .vlc {
            _ = vlcBridge.applyAudioPreset(preset)
        }
        showHUD("Audio: \(preset.rawValue)")
    }

    private func adjustAudioDelay(by delta: Double) {
        setAudioDelay(audioDelayStepper.doubleValue + delta)
    }

    private func setAudioDelay(_ delay: Double) {
        let clampedDelay = min(max(delay, audioDelayStepper.minValue), audioDelayStepper.maxValue)
        audioDelayStepper.doubleValue = clampedDelay
        audioDelayLabel.stringValue = String(format: "%.1fs", clampedDelay)
        guard currentEngine == .vlc else {
            showHUD("Audio delay needs VLC playback")
            return
        }
        if vlcBridge.setAudioDelay(seconds: clampedDelay) {
            showHUD("Audio delay \(String(format: "%.1fs", clampedDelay))")
        }
    }

    private func applyVideoAdjustments(showHUD shouldShowHUD: Bool) {
        guard currentEngine == .vlc else {
            if shouldShowHUD {
                showHUD("Video adjustments need VLC playback")
            }
            return
        }

        if vlcBridge.applyVideoAdjustments(currentVideoAdjustments), shouldShowHUD {
            showHUD(currentVideoAdjustments.isDefault ? "Video reset" : "Video adjusted")
        }
    }

    private func makeVideoAdjustmentRow(for key: VideoAdjustmentKey) -> NSView {
        let label = NSTextField(labelWithString: key.title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let slider = NSSlider(
            value: videoAdjustmentValue(for: key),
            minValue: key.range.lowerBound,
            maxValue: key.range.upperBound,
            target: self,
            action: #selector(videoAdjustmentSliderChanged(_:))
        )
        slider.identifier = NSUserInterfaceItemIdentifier(key.rawValue)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        slider.setAccessibilityLabel(key.title)
        slider.setAccessibilityHelp("Adjust video \(key.title.lowercased()).")
        videoAdjustmentSliders[key] = slider

        let stack = NSStackView(views: [label, slider])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func videoAdjustmentValue(for key: VideoAdjustmentKey) -> Double {
        switch key {
        case .brightness:
            currentVideoAdjustments.brightness
        case .contrast:
            currentVideoAdjustments.contrast
        case .saturation:
            currentVideoAdjustments.saturation
        case .hue:
            currentVideoAdjustments.hue
        case .gamma:
            currentVideoAdjustments.gamma
        }
    }

    private func nextScreenshotURL() throws -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        let folder = pictures.appendingPathComponent("Video Player Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let fileName = "video-frame-\(formatter.string(from: Date())).png"
        return folder.appendingPathComponent(fileName)
    }

    private func takeNativeScreenshot(to url: URL) throws {
        guard let item = currentItem else { throw NSError(domain: "VideoPlayer", code: 1) }
        let asset = AVURLAsset(url: item.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let image = try generator.copyCGImage(at: avPlayer.currentTime(), actualTime: nil)
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VideoPlayer", code: 2)
        }
        try data.write(to: url)
    }

    private func startCodecTimer() {
        codecTimer?.invalidate()
        codecTickCount = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateCodecTimeline()
        }
        RunLoop.main.add(timer, forMode: .common)
        codecTimer = timer
    }

    private func updateCodecTimeline() {
        guard currentEngine == .vlc, !isScrubbing else { return }
        let currentSeconds = vlcBridge.currentTime
        let durationSeconds = vlcBridge.duration
        codecTickCount += 1

        currentTimeLabel.stringValue = formatTime(currentSeconds)
        savePosition(currentSeconds, duration: durationSeconds)
        enforceLoopIfNeeded(currentSeconds)

        if durationSeconds.isFinite && durationSeconds > 0 {
            seekSlider.maxValue = durationSeconds
            seekSlider.doubleValue = min(currentSeconds, durationSeconds)
            durationLabel.stringValue = formatTime(durationSeconds)
        } else {
            seekSlider.maxValue = 1
            seekSlider.doubleValue = 0
            durationLabel.stringValue = "0:00"
        }

        if codecTickCount % 8 == 0 {
            refreshTrackMenus()
        }
    }

    private func updateTimeline(currentTime: CMTime) {
        guard currentEngine == .native, !isScrubbing else { return }
        let currentSeconds = currentTime.seconds
        guard currentSeconds.isFinite else { return }

        currentTimeLabel.stringValue = formatTime(currentSeconds)

        let durationSeconds = avPlayer.currentItem?.duration.seconds ?? 0
        savePosition(currentSeconds, duration: durationSeconds)
        enforceLoopIfNeeded(currentSeconds)
        if durationSeconds.isFinite && durationSeconds > 0 {
            seekSlider.maxValue = durationSeconds
            seekSlider.doubleValue = min(currentSeconds, durationSeconds)
            durationLabel.stringValue = formatTime(durationSeconds)
        } else {
            seekSlider.maxValue = 1
            seekSlider.doubleValue = 0
            durationLabel.stringValue = "0:00"
        }
    }

    private func handleVLCEvent(_ event: VLCPlaybackEvent) {
        guard currentEngine == .vlc else { return }

        switch event {
        case .opening:
            engineLabel.stringValue = "Opening with VLC codec engine"
        case .buffering:
            engineLabel.stringValue = "Buffering with VLC codec engine"
        case .playing:
            engineLabel.stringValue = "Playing in-app with VLC codec engine"
            refreshControls()
        case .paused:
            engineLabel.stringValue = "Paused"
            refreshControls()
        case .stopped:
            refreshControls()
        case .ended:
            if let currentItem {
                stateStore.clearPosition(for: currentItem)
            }
            playNext(nil)
        case .error:
            currentEngine = .none
            engineLabel.stringValue = "VLC encountered a playback error."
            vlcVideoSurface.isHidden = true
            playerView.isHidden = false
            resetTrackMenus()
            refreshControls()
        case .lengthChanged:
            updateCodecTimeline()
        case .chapterChanged:
            showHUD("Chapter changed")
        case .tracksChanged:
            refreshTrackMenus()
        }
    }

    private func updateNowPlaying(title: String, detail: String) {
        nowPlayingLabel.stringValue = title
        engineLabel.stringValue = detail
    }

    private func refreshControls() {
        let isPlaying = avPlayer.timeControlStatus == .playing
            || (currentEngine == .vlc && vlcBridge.isPlaying)
            || (currentEngine == .mpv && mpvBridge.isRunning)
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: isPlaying ? "Pause" : "Play"
        )
        playPauseButton.setAccessibilityLabel(isPlaying ? "Pause" : "Play")
        updateSidebarButton(sidebarHidden: sidebarView?.isHidden == true)
        updateEmptyState()
        refreshPlaylistActionStates()
    }

    private func updateSidebarButton(sidebarHidden: Bool) {
        sidebarButton.image = NSImage(
            systemSymbolName: sidebarHidden ? "sidebar.left" : "sidebar.left",
            accessibilityDescription: sidebarHidden ? "Show sidebar" : "Hide sidebar"
        )
        sidebarButton.toolTip = sidebarHidden ? "Show sidebar" : "Hide sidebar"
        sidebarButton.setAccessibilityLabel(sidebarHidden ? "Show sidebar" : "Hide sidebar")
    }

    private func updateEmptyState() {
        emptyStateContainer.isHidden = !playlist.isEmpty || currentEngine != .none
    }

    private func configureEmptyStateButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.toolTip = button.title
        button.setAccessibilityLabel(button.title)
        button.setAccessibilityHelp(button.title)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true
    }

    private func iconButton(
        systemName: String,
        description: String,
        action: Selector,
        controlBarStyle: Bool = false
    ) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemName, accessibilityDescription: description)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = description
        button.setAccessibilityLabel(description)
        button.setAccessibilityHelp(description)
        if controlBarStyle {
            button.appearance = NSAppearance(named: .darkAqua)
            button.contentTintColor = .white
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func loadSubtitle(_ url: URL) {
        guard currentEngine == .vlc else {
            showHUD("Subtitles need VLC playback")
            return
        }

        if vlcBridge.addSubtitle(url: url) {
            showHUD("Subtitle loaded")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshTrackMenus()
            }
        } else {
            showHUD("Subtitle failed")
        }
    }

    private func autoLoadSidecarSubtitle(for item: MediaItem) {
        guard item.url.isFileURL else { return }
        let baseURL = item.url.deletingPathExtension()
        let candidates = subtitleExtensions.map { baseURL.appendingPathExtension($0) }
        guard let subtitleURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.loadSubtitle(subtitleURL)
        }
    }

    private func scheduleTrackMenuRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshTrackMenus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.refreshTrackMenus()
        }
    }

    private func refreshTrackMenus() {
        guard currentEngine == .vlc else {
            resetTrackMenus()
            return
        }

        isUpdatingTrackMenus = true
        populate(audioTrackPopup, options: vlcBridge.audioTracks(), selectedID: vlcBridge.selectedAudioTrackID(), emptyTitle: "Audio Track")

        let audioDelay = vlcBridge.audioDelaySeconds()
        audioDelayStepper.doubleValue = audioDelay
        audioDelayLabel.stringValue = String(format: "%.1fs", audioDelay)
        audioDelayStepper.isEnabled = true

        var subtitles = vlcBridge.subtitleTracks()
        if !subtitles.contains(where: { $0.id == -1 }) {
            subtitles.insert(TrackOption(id: -1, name: "Subtitles Off"), at: 0)
        }
        populate(subtitleTrackPopup, options: subtitles, selectedID: vlcBridge.selectedSubtitleTrackID(), emptyTitle: "Subtitles")

        let delay = vlcBridge.subtitleDelaySeconds()
        subtitleDelayStepper.doubleValue = delay
        subtitleDelayLabel.stringValue = String(format: "%.1fs", delay)
        subtitleDelayStepper.isEnabled = true
        subtitleTrackPopup.isEnabled = subtitleTrackPopup.numberOfItems > 0
        audioTrackPopup.isEnabled = audioTrackPopup.numberOfItems > 0
        isUpdatingTrackMenus = false
    }

    private func resetTrackMenus() {
        isUpdatingTrackMenus = true
        audioTrackPopup.removeAllItems()
        audioTrackPopup.addItem(withTitle: "Audio Track")
        audioTrackPopup.isEnabled = false
        audioDelayStepper.doubleValue = 0
        audioDelayStepper.isEnabled = false
        audioDelayLabel.stringValue = "0.0s"
        subtitleTrackPopup.removeAllItems()
        subtitleTrackPopup.addItem(withTitle: "Subtitles")
        subtitleTrackPopup.isEnabled = false
        subtitleDelayStepper.doubleValue = 0
        subtitleDelayStepper.isEnabled = false
        subtitleDelayLabel.stringValue = "0.0s"
        isUpdatingTrackMenus = false
    }

    private func populate(_ popup: NSPopUpButton, options: [TrackOption], selectedID: Int32?, emptyTitle: String) {
        popup.removeAllItems()
        if options.isEmpty {
            popup.addItem(withTitle: emptyTitle)
            popup.isEnabled = false
            return
        }

        for option in options {
            popup.addItem(withTitle: option.name)
            popup.lastItem?.representedObject = NSNumber(value: option.id)
        }

        if let selectedID, let item = popup.itemArray.first(where: { ($0.representedObject as? NSNumber)?.int32Value == selectedID }) {
            popup.select(item)
        }
        popup.isEnabled = true
    }

    private func selectedTrackID(from popup: NSPopUpButton) -> Int32? {
        (popup.selectedItem?.representedObject as? NSNumber)?.int32Value
    }

    private func showHUD(_ text: String) {
        hudTimer?.invalidate()
        hudLabel.stringValue = text
        hudLabel.alphaValue = 1
        hudLabel.isHidden = false

        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.hudLabel.animator().alphaValue = 0
            } completionHandler: {
                self.hudLabel.isHidden = true
                self.hudLabel.alphaValue = 1
            }
        }
    }

    private func restorePersistentState() {
        setVolume(stateStore.loadVolume(default: defaultVolume), persist: false)
        if let speedTitle = stateStore.loadSpeedTitle(), speedPopup.itemTitles.contains(speedTitle) {
            speedPopup.selectItem(withTitle: speedTitle)
        }
        if let presetTitle = stateStore.loadAudioPreset(), let preset = AudioPreset(rawValue: presetTitle) {
            currentAudioPreset = preset
            audioPresetPopup.selectItem(withTitle: preset.rawValue)
        }
        if let sortModeValue = stateStore.loadPlaylistSortMode(),
           let sortMode = PlaylistSortMode(rawValue: sortModeValue) {
            playlistSortMode = sortMode
            playlistSortPopup.selectItem(withTitle: sortMode.title)
        }

        let restored = stateStore.loadPlaylist()
        playlist = restored.0
        let restoredItem = restored.1.flatMap { playlist.indices.contains($0) ? playlist[$0] : nil }
        sortPlaylistPreserving(item: restoredItem)
        if let restoredItem {
            currentIndex = playlist.firstIndex(of: restoredItem)
        }

        tableView.reloadData()
        if let currentIndex {
            restoreVisiblePlaylistSelection()
            let item = playlist[currentIndex]
            updateNowPlaying(title: item.title, detail: "Restored playlist")
            updateMetadata(for: item)
        }
        loadManagedKioskPlaylistIfNeeded()
        refreshPlaylistActionStates()
    }

    private func loadManagedKioskPlaylistIfNeeded() {
        let policy = EnterprisePolicy.snapshot()
        guard policy.kioskModeEnabled, let url = policy.kioskPlaylistURL else { return }
        AppLogger.info("Loading managed kiosk playlist url=\(url.absoluteString)", flush: true)
        addMedia(from: [url], replacePlaylist: true, autoplay: false)
        if let window = view.window {
            window.toggleFullScreen(nil)
        }
        showHUD("Kiosk playlist loaded")
    }

    private func savePlaylistState() {
        stateStore.savePlaylist(playlist, currentIndex: currentIndex)
    }

    private func saveCurrentPosition() {
        guard let item = currentItem else { return }
        switch currentEngine {
        case .native:
            let current = avPlayer.currentTime().seconds
            let duration = avPlayer.currentItem?.duration.seconds ?? 0
            savePosition(current, duration: duration, item: item)
        case .vlc:
            savePosition(vlcBridge.currentTime, duration: vlcBridge.duration, item: item)
        case .mpv, .none:
            break
        }
    }

    private func savePosition(_ seconds: Double, duration: Double) {
        guard let currentItem else { return }
        savePosition(seconds, duration: duration, item: currentItem)
    }

    private func savePosition(_ seconds: Double, duration: Double, item: MediaItem) {
        guard seconds.isFinite, seconds > 5 else { return }
        if duration.isFinite, duration > 0, seconds > duration - 10 {
            stateStore.clearPosition(for: item)
        } else {
            stateStore.savePosition(seconds, for: item)
        }
    }

    private func promptedResumeTime(for item: MediaItem) -> Double? {
        let savedPosition = stateStore.position(for: item)
        guard savedPosition > 15 else { return nil }

        let alert = NSAlert()
        alert.messageText = "Resume Playback?"
        alert.informativeText = "\(item.title) was last played at \(formatTime(savedPosition))."
        alert.addButton(withTitle: "Resume")
        alert.addButton(withTitle: "Start Over")

        if alert.runModal() == .alertFirstButtonReturn {
            return savedPosition
        }

        stateStore.clearPosition(for: item)
        return nil
    }

    private func applyResumeTime(_ resumeTime: Double?) {
        guard let resumeTime else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard self?.currentEngine == .vlc else { return }
            self?.vlcBridge.setTime(resumeTime)
            self?.showHUD("Resumed at \(self?.formatTime(resumeTime) ?? "saved time")")
        }
    }

    private func selectItemForInspection(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        restoreVisiblePlaylistSelection()
        let item = playlist[index]
        updateMetadata(for: item)
        updateNowPlaying(title: item.title, detail: "Ready to play")
        savePlaylistState()
    }

    private func updateMetadataForSelection() {
        let row = tableView.selectedRow
        guard let playlistIndex = playlistIndex(forVisibleRow: row) else {
            metadataRequestID += 1
            if !playlistFilter.isEmpty, !playlist.isEmpty, visiblePlaylistIndices.isEmpty {
                metadataTextView.stringValue = "No playlist items match \"\(playlistFilter)\"."
            } else {
                metadataTextView.stringValue = "Select a media item to inspect it before playback."
            }
            return
        }
        updateMetadata(for: playlist[playlistIndex])
    }

    private func updateMetadata(for item: MediaItem) {
        metadataRequestID += 1
        let requestID = metadataRequestID
        let savedPosition = stateStore.position(for: item)
        metadataTextView.stringValue = "Loading metadata for \(item.title)..."

        Task { [weak self] in
            let vlcInspection = await Task.detached(priority: .utility) {
                VLCBridge.inspectMedia(url: item.url)
            }.value
            let metadata = await MediaMetadata.inspect(
                item: item,
                savedPosition: savedPosition,
                vlcInspection: vlcInspection
            )
            await MainActor.run { [weak self] in
                guard let self, self.metadataRequestID == requestID else { return }
                let extraDetails = metadata.extraDetails.isEmpty
                    ? ""
                    : "\n\n\(metadata.extraDetails.joined(separator: "\n"))"
                let libraryRecord = self.stateStore.mediaLibraryRecord(for: item)
                let libraryDetails = """
                Favorite: \(libraryRecord.isFavorite ? "Yes" : "No")
                Watched: \(libraryRecord.isWatched ? "Yes" : "No")
                Tags: \(libraryRecord.tags.isEmpty ? "--" : libraryRecord.tags.joined(separator: ", "))
                """
                self.metadataTextView.stringValue = """
                \(metadata.title)

                Type: \(metadata.kind)
                Size: \(metadata.size)
                Duration: \(metadata.duration)
                Video: \(metadata.dimensions)
                Modified: \(metadata.modified)
                Resume: \(metadata.savedPosition)

                \(metadata.location)
                \(libraryDetails)
                \(extraDetails)
                """
            }
        }
    }

    private func rebuildLibraryFolderRows() {
        guard let libraryFoldersStack else { return }
        libraryFoldersStack.arrangedSubviews.forEach {
            libraryFoldersStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if !stateStore.savePlaybackHistoryEnabled() {
            let label = libraryMessageLabel(
                "Library folders are not saved while playback history is off or disabled by policy."
            )
            libraryFoldersStack.addArrangedSubview(label)
            return
        }

        let folders = stateStore.loadLibraryFolders()
        guard !folders.isEmpty else {
            libraryFoldersStack.addArrangedSubview(libraryMessageLabel("No library folders saved."))
            return
        }

        for (index, folder) in folders.enumerated() {
            let label = NSTextField(labelWithString: folder.path)
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setAccessibilityLabel("Library folder \(index + 1)")
            label.setAccessibilityValue(folder.path)

            let removeButton = iconButton(
                systemName: "minus.circle",
                description: "Remove library folder",
                action: #selector(removeLibraryFolderFromManager(_:))
            )
            removeButton.tag = index

            let row = NSStackView(views: [label, removeButton])
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.widthAnchor.constraint(equalTo: libraryFoldersStack.widthAnchor).isActive = true
            libraryFoldersStack.addArrangedSubview(row)
        }
    }

    private func libraryMessageLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func shouldIncludeLogsInSupportBundle(policy: EnterprisePolicySnapshot) -> Bool? {
        guard !policy.disableSupportBundleLogExport else {
            showHUD("Logs omitted by policy")
            return false
        }

        let alert = NSAlert()
        alert.messageText = "Include Diagnostic Logs?"
        alert.informativeText = policy.redactSupportBundlePaths
            ? "The support bundle can include the app log with home folders, volume paths, stream credentials, and tokens redacted."
            : "The support bundle can include the app log. Your current policy does not redact local paths."
        alert.addButton(withTitle: "Include Logs")
        alert.addButton(withTitle: "No Logs")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }

    @MainActor
    private func currentPlaybackDiagnosticReport() async -> PlaybackDiagnosticReport {
        let item = selectedOrCurrentItem
        let assessment: NativePlaybackAssessment?
        if let item, item.url.isFileURL {
            assessment = await NativePlaybackPolicy.assessment(for: item, nativeExtensions: nativeExtensions)
        } else {
            assessment = item == nil ? nil : .native
        }

        let resolvedAddresses = item.flatMap {
            networkStreamResolutions[$0.url.absoluteString]
        } ?? []

        return PlaybackDiagnostics.report(input: PlaybackDiagnosticInput(
            item: item,
            nativeAssessment: assessment,
            externalEnginesAvailable: AppSecurityPolicy.externalMediaEnginesAvailable,
            externalEnginesEnabled: stateStore.externalMediaEnginesEnabled(),
            vlcAvailable: vlcBridge.isAvailable,
            mpvAvailable: mpvBridge.isAvailable,
            policy: EnterprisePolicy.snapshot(),
            licenseStatus: EnterpriseLicenseManager.status(),
            resolvedStreamAddresses: resolvedAddresses
        ))
    }

    private func showTextDialog(title: String, text: String, height: CGFloat) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 660, height: height))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.runModal()
    }

    private var currentItem: MediaItem? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    private var selectedOrCurrentItem: MediaItem? {
        if let index = playlistIndex(forVisibleRow: tableView.selectedRow) {
            return playlist[index]
        }
        return currentItem
    }

    private func rememberValidatedNetworkStream(_ stream: NetworkStreamValidator.ValidatedStream) {
        guard stream.url.isFileURL == false else { return }
        networkStreamResolutions[stream.url.absoluteString] = stream.resolvedAddresses
    }

    private func networkStreamResolutionChanged(_ stream: NetworkStreamValidator.ValidatedStream) -> Bool {
        let currentAddresses = stream.resolvedAddresses
        guard !currentAddresses.isEmpty,
              let previousAddresses = networkStreamResolutions[stream.url.absoluteString],
              !previousAddresses.isEmpty
        else {
            return false
        }
        return previousAddresses.isDisjoint(with: currentAddresses)
    }

    private var visiblePlaylistIndices: [Int] {
        PlaylistWorkflow.visibleIndices(in: playlist, filter: playlistFilter)
    }

    private func playlistIndex(forVisibleRow row: Int) -> Int? {
        let indices = visiblePlaylistIndices
        guard indices.indices.contains(row) else { return nil }
        return indices[row]
    }

    private func restoreVisiblePlaylistSelection() {
        guard let currentIndex, let row = visiblePlaylistIndices.firstIndex(of: currentIndex) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func selectedPlaylistIndices() -> [Int] {
        tableView.selectedRowIndexes.compactMap(playlistIndex(forVisibleRow:)).sorted()
    }

    private func selectNearestPlaylistRow(afterRemovingVisibleRows removedRows: IndexSet) {
        guard currentIndex == nil, !playlist.isEmpty, !visiblePlaylistIndices.isEmpty else {
            restoreVisiblePlaylistSelection()
            return
        }

        let candidateRow = min(removedRows.first ?? 0, visiblePlaylistIndices.count - 1)
        guard let index = playlistIndex(forVisibleRow: candidateRow) else { return }
        currentIndex = index
        tableView.selectRowIndexes(IndexSet(integer: candidateRow), byExtendingSelection: false)
        updateMetadata(for: playlist[index])
        updateNowPlaying(title: playlist[index].title, detail: "Ready to play")
    }

    private func refreshPlaylistActionStates() {
        removePlaylistButton?.isEnabled = !selectedPlaylistIndices().isEmpty
        clearPlaylistButton?.isEnabled = !playlist.isEmpty
    }

    private var canReorderPlaylist: Bool {
        playlistSortMode == .currentOrder && playlistFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reorderPlaylistItems(at sourceIndexes: [Int], to proposedRow: Int) {
        let activeItem = currentItem
        let movingIndexes = Array(Set(sourceIndexes)).sorted()
        guard !movingIndexes.isEmpty, movingIndexes.allSatisfy({ playlist.indices.contains($0) }) else { return }

        let movingItems = movingIndexes.map { playlist[$0] }
        playlist = PlaylistWorkflow.reordered(playlist, movingIndexes: movingIndexes, to: proposedRow)

        if let activeItem {
            currentIndex = playlist.firstIndex(of: activeItem)
        }

        tableView.reloadData()
        let selectedRows = movingItems.compactMap { playlist.firstIndex(of: $0) }
        var selectedRowIndexes = IndexSet()
        selectedRows.forEach { selectedRowIndexes.insert($0) }
        tableView.selectRowIndexes(selectedRowIndexes, byExtendingSelection: false)
        if let firstRow = selectedRows.first {
            tableView.scrollRowToVisible(firstRow)
        }
        savePlaylistState()
        refreshPlaylistActionStates()
        showHUD("Moved \(movingItems.count) item\(movingItems.count == 1 ? "" : "s")")
    }

    private func playlistIndexes(from pasteboard: NSPasteboard) -> [Int] {
        let strings = pasteboard.pasteboardItems?.compactMap {
            $0.string(forType: .videoPlayerPlaylistRows)
        } ?? []

        return Array(Set(strings.flatMap { value in
            value.split(separator: ",").compactMap { Int($0) }
        })).sorted()
    }

    private func clearPlaylistFilter() {
        guard !playlistFilter.isEmpty || !playlistSearchField.stringValue.isEmpty else { return }
        playlistFilter = ""
        playlistSearchField.stringValue = ""
    }

    @MainActor
    private func importPlaylist(from url: URL, replacePlaylist: Bool) async {
        do {
            let result = try await importedPlaylistItems(from: url)
            guard !result.items.isEmpty else {
                showPlaylistFileError(
                    title: "No Supported Media Found",
                    detail: result.issueSummary.isEmpty
                        ? "The playlist did not contain supported local media files or allowed public stream URLs."
                        : result.issueSummary
                )
                return
            }

            addMediaItems(result.items, replacePlaylist: replacePlaylist, autoplay: false)
            let skippedText = result.skippedCount > 0 ? ", skipped \(result.skippedCount)" : ""
            showHUD("Imported \(result.items.count)\(skippedText)")
            if !result.issues.isEmpty {
                showPlaylistFileError(
                    title: "Playlist Imported with Skipped Entries",
                    detail: result.issueSummary
                )
            }
        } catch {
            showPlaylistFileError(
                title: "Could Not Import Playlist",
                detail: "The playlist could not be read. \(error.localizedDescription)"
            )
        }
    }

    private func importedPlaylistItems(from playlistURL: URL) async throws -> PlaylistImportResult {
        let contents = try String(contentsOf: playlistURL, encoding: .utf8)
        let baseDirectory = playlistURL.deletingLastPathComponent()
        var items: [MediaItem] = []
        var issues: [PlaylistImportIssue] = []

        for (offset, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let entry = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }

            let result = await mediaItems(fromPlaylistEntry: entry, lineNumber: offset + 1, baseDirectory: baseDirectory)
            if result.items.isEmpty, let issue = result.issue {
                issues.append(issue)
            } else {
                items.append(contentsOf: result.items)
            }
        }

        return PlaylistImportResult(items: items, issues: issues)
    }

    private func mediaItems(fromPlaylistEntry entry: String, lineNumber: Int, baseDirectory: URL) async -> PlaylistEntryImportResult {
        if let url = URL(string: entry), let scheme = url.scheme, !scheme.isEmpty {
            if url.isFileURL {
                let items = mediaURLs(from: url).map(MediaItem.init(url:))
                return PlaylistEntryImportResult(
                    items: items,
                    issue: items.isEmpty ? playlistImportIssue(for: url, lineNumber: lineNumber, entry: entry) : nil
                )
            }

            let validatedStream = await NetworkStreamValidator.validatedStream(
                from: entry,
                allowPrivateNetworkHosts: stateStore.privateNetworkStreamsEnabled()
            )
            if let validatedStream {
                rememberValidatedNetworkStream(validatedStream)
                return PlaylistEntryImportResult(items: [MediaItem(url: validatedStream.url)], issue: nil)
            }
            return PlaylistEntryImportResult(
                items: [],
                issue: PlaylistImportIssue(
                    lineNumber: lineNumber,
                    entry: entry,
                    reason: "Stream URL is invalid, unsupported, private/local, or could not be resolved."
                )
            )
        }

        let fileURL = PlaylistWorkflow.fileURL(fromPlaylistEntry: entry, baseDirectory: baseDirectory)
        let items = mediaURLs(from: fileURL).map(MediaItem.init(url:))
        return PlaylistEntryImportResult(
            items: items,
            issue: items.isEmpty ? playlistImportIssue(for: fileURL, lineNumber: lineNumber, entry: entry) : nil
        )
    }

    private func playlistImportIssue(for url: URL, lineNumber: Int, entry: String) -> PlaylistImportIssue {
        guard url.isFileURL else {
            return PlaylistImportIssue(lineNumber: lineNumber, entry: entry, reason: "Unsupported URL.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return PlaylistImportIssue(lineNumber: lineNumber, entry: entry, reason: "File does not exist.")
        }

        if isDirectory.boolValue {
            return PlaylistImportIssue(lineNumber: lineNumber, entry: entry, reason: "Folder contains no supported media.")
        }

        return PlaylistImportIssue(lineNumber: lineNumber, entry: entry, reason: "Unsupported media type.")
    }

    private func exportedPlaylistText() -> String {
        PlaylistWorkflow.exportedM3U8Text(for: playlist)
    }

    private func showPlaylistFileError(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.addButton(withTitle: "OK")

        if detail.contains("\n") || detail.count > 240 {
            alert.informativeText = "Review the entries below."
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 220))
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder

            let textView = NSTextView(frame: scrollView.bounds)
            textView.string = detail
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textColor = .labelColor
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.autoresizingMask = [.width]
            textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: .greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            scrollView.documentView = textView
            alert.accessoryView = scrollView
        } else {
            alert.informativeText = detail
        }
        alert.runModal()
    }

    private func sortPlaylistPreservingCurrentItem() {
        sortPlaylistPreserving(item: currentItem)
    }

    private func sortPlaylistPreserving(item selectedItem: MediaItem?) {
        guard playlistSortMode != .currentOrder else { return }
        PlaylistWorkflow.sort(&playlist, by: playlistSortMode)
        if let selectedItem {
            currentIndex = playlist.firstIndex(of: selectedItem)
        }
    }

    private func confirmClearPlaylist() -> Bool {
        guard !playlist.isEmpty else {
            showHUD("Playlist is empty")
            return false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Playlist?"
        alert.informativeText = "This removes all items from the current playlist. Media files on disk are not deleted."
        alert.addButton(withTitle: "Clear Playlist")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        guard let index = playlistIndex(forVisibleRow: sender.clickedRow) else { return }
        playItem(at: index)
    }

    @objc private func playerDidFinish(_ notification: Notification) {
        guard currentEngine == .native else { return }
        if let currentItem {
            stateStore.clearPosition(for: currentItem)
        }
        playNext(nil)
    }

    @objc private func playerFailed(_ notification: Notification) {
        guard let index = currentIndex else { return }
        handleNativeFailure(for: playlist[index], fallbackToMPV: true, error: avPlayer.currentItem?.error)
    }

    @objc private func toggleFullscreen(_ sender: Any?) {
        view.window?.toggleFullScreen(sender)
    }
}

extension PlayerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visiblePlaylistIndices.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if currentEngine == .none {
            let row = tableView.selectedRow
            if let index = playlistIndex(forVisibleRow: row) {
                currentIndex = index
                updateNowPlaying(title: playlist[index].title, detail: "Ready to play")
                savePlaylistState()
            }
        }
        updateMetadataForSelection()
        refreshPlaylistActionStates()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard canReorderPlaylist, let index = playlistIndex(forVisibleRow: row) else { return nil }
        let selectedIndexes = selectedPlaylistIndices()
        let indexesToWrite = selectedIndexes.contains(index) ? selectedIndexes : [index]
        let item = NSPasteboardItem()
        item.setString(indexesToWrite.map(String.init).joined(separator: ","), forType: .videoPlayerPlaylistRows)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard canReorderPlaylist,
              info.draggingPasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.videoPlayerPlaylistRows.rawValue])
        else {
            return []
        }

        tableView.setDropRow(max(row, 0), dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard canReorderPlaylist else { return false }
        let sourceIndexes = playlistIndexes(from: info.draggingPasteboard)
        guard !sourceIndexes.isEmpty else { return false }
        reorderPlaylistItems(at: sourceIndexes, to: row < 0 ? playlist.count : row)
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MediaCell")
        guard let index = playlistIndex(forVisibleRow: row) else { return nil }
        let item = playlist[index]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? MediaCellView ?? MediaCellView()
        cell.identifier = identifier
        cell.configure(title: item.title, subtitle: item.isNetworkStream ? "STREAM" : item.fileExtension.uppercased())
        return cell
    }
}

extension PlayerViewController: DropViewDelegate {
    func dropView(_ dropView: DropView, didReceive urls: [URL]) {
        addMedia(from: urls, replacePlaylist: playlist.isEmpty, autoplay: false)
    }
}

extension PlayerViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSPanel === videoAdjustmentPanel {
            videoAdjustmentPanel = nil
            videoAdjustmentSliders = [:]
        } else if notification.object as? NSPanel === libraryPanel {
            libraryPanel = nil
            libraryFoldersStack = nil
        }
    }
}

private extension NSPasteboard.PasteboardType {
    static let videoPlayerPlaylistRows = NSPasteboard.PasteboardType("com.jaysonguglietta.videoplayer.playlist.rows")
}

private enum PlaybackEngine {
    case none
    case native
    case vlc
    case mpv
}
