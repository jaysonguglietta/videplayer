import AppKit
import AVFoundation
import AVKit

final class PlayerViewController: NSViewController {
    private let maximumVolume = 200.0
    private let defaultVolume = 70.0
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
    private var currentVideoAdjustments = VideoAdjustments()
    private var videoAdjustmentPanel: NSPanel?
    private var videoAdjustmentSliders: [VideoAdjustmentKey: NSSlider] = [:]

    private let playerView = AVPlayerView()
    private let vlcVideoSurface = NSView()
    private weak var splitView: NSSplitView?
    private weak var sidebarView: NSView?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private weak var playerAreaView: NSView?
    private let tableView = NSTableView()
    private let metadataTextView = NSTextField(labelWithString: "Select a media item to inspect it before playback.")
    private let emptyStateLabel = NSTextField(labelWithString: "Drop media files here or open a file")
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
        saveCurrentPosition()
        savePlaylistState()
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
        }
        codecTimer?.invalidate()
        hudTimer?.invalidate()
        vlcBridge.stop()
        mpvBridge.stop()
    }

    @objc func openFilesPanel(replacePlaylist: Bool) {
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

    @objc func openNetworkStreamDialog(_ sender: Any? = nil) {
        let alert = NSAlert()
        alert.messageText = "Open Network Stream"
        alert.informativeText = "Enter an HTTP, HTTPS, RTSP, or HLS stream URL."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "https://example.com/stream.m3u8"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = NetworkStreamValidator.validatedURL(from: input.stringValue) else {
            showHUD("Use HTTP, HTTPS, RTSP, or HLS")
            return
        }

        addMediaItems([MediaItem(url: url)], replacePlaylist: playlist.isEmpty, autoplay: false)
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

    @objc func chooseLibraryFolder(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add Library Folder"
        panel.message = "Choose a folder to scan for media."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        stateStore.addLibraryFolder(url)
        addMedia(from: [url], replacePlaylist: playlist.isEmpty, autoplay: false)
        showHUD("Library folder added")
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
        stopPlayback()
        playlist.removeAll()
        currentIndex = nil
        loopStart = nil
        loopEnd = nil
        tableView.reloadData()
        updateEmptyState()
        updateNowPlaying(title: "Ready", detail: "")
        metadataRequestID += 1
        metadataTextView.stringValue = "Select a media item to inspect it before playback."
        savePlaylistState()
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
        let clearButton = iconButton(systemName: "trash", description: "Clear playlist", action: #selector(clearPlaylist(_:)))
        let hideSidebarButton = iconButton(systemName: "sidebar.left", description: "Hide sidebar", action: #selector(toggleSidebar(_:)))

        header.addArrangedSubview(title)
        header.addArrangedSubview(openButton)
        header.addArrangedSubview(clearButton)
        header.addArrangedSubview(hideSidebarButton)

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 54
        tableView.style = .sourceList
        tableView.allowsEmptySelection = true
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))

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

        metadataPanel.addSubview(metadataTitle)
        metadataPanel.addSubview(metadataTextView)

        container.addSubview(header)
        container.addSubview(scrollView)
        container.addSubview(metadataPanel)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
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

        vlcVideoSurface.translatesAutoresizingMaskIntoConstraints = false
        vlcVideoSurface.wantsLayer = true
        vlcVideoSurface.layer?.backgroundColor = NSColor.black.cgColor
        vlcVideoSurface.isHidden = true

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 21, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center

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

        let controls = makeControls()
        controls.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(playerView)
        container.addSubview(vlcVideoSurface)
        container.addSubview(emptyStateLabel)
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

            emptyStateLabel.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: playerView.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: playerView.trailingAnchor, constant: -24),

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
        speedPopup.widthAnchor.constraint(equalToConstant: 78).isActive = true

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        volumeSlider.toolTip = "Volume boost"
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
        audioTrackPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        audioPresetPopup.addItems(withTitles: AudioPreset.allCases.map(\.rawValue))
        audioPresetPopup.selectItem(withTitle: currentAudioPreset.rawValue)
        audioPresetPopup.target = self
        audioPresetPopup.action = #selector(audioPresetChanged(_:))
        audioPresetPopup.toolTip = "Audio preset"
        audioPresetPopup.widthAnchor.constraint(equalToConstant: 132).isActive = true

        audioDelayStepper.minValue = -30
        audioDelayStepper.maxValue = 30
        audioDelayStepper.increment = 0.1
        audioDelayStepper.target = self
        audioDelayStepper.action = #selector(audioDelayChanged(_:))
        audioDelayStepper.toolTip = "Audio delay"
        audioDelayStepper.widthAnchor.constraint(equalToConstant: 52).isActive = true

        audioDelayLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        audioDelayLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        audioDelayLabel.alignment = .right
        audioDelayLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        subtitleTrackPopup.target = self
        subtitleTrackPopup.action = #selector(subtitleTrackChanged(_:))
        subtitleTrackPopup.toolTip = "Subtitle track"
        subtitleTrackPopup.widthAnchor.constraint(equalToConstant: 230).isActive = true

        subtitleDelayStepper.minValue = -30
        subtitleDelayStepper.maxValue = 30
        subtitleDelayStepper.increment = 0.1
        subtitleDelayStepper.target = self
        subtitleDelayStepper.action = #selector(subtitleDelayChanged(_:))
        subtitleDelayStepper.toolTip = "Subtitle delay"
        subtitleDelayStepper.widthAnchor.constraint(equalToConstant: 52).isActive = true

        subtitleDelayLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        subtitleDelayLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        subtitleDelayLabel.alignment = .right
        subtitleDelayLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let audioIcon = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio") ?? NSImage())
        audioIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        audioIcon.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        let subtitleIcon = NSImageView(image: NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "Subtitles") ?? NSImage())
        subtitleIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        subtitleIcon.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        let loadSubtitleButton = iconButton(systemName: "text.badge.plus", description: "Load subtitles", action: #selector(openSubtitlePanel(_:)), controlBarStyle: true)

        let gap = NSView()
        gap.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            audioIcon,
            audioTrackPopup,
            audioPresetPopup,
            audioDelayStepper,
            audioDelayLabel,
            subtitleIcon,
            subtitleTrackPopup,
            loadSubtitleButton,
            subtitleDelayStepper,
            subtitleDelayLabel,
            gap
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
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
        if replacePlaylist {
            stopPlayback()
            playlist = items
            currentIndex = nil
        } else {
            playlist.append(contentsOf: items)
        }

        tableView.reloadData()
        updateEmptyState()
        savePlaylistState()

        if currentIndex == nil, autoplay {
            playItem(at: replacePlaylist ? 0 : playlist.count - items.count)
        } else if currentIndex == nil {
            let index = replacePlaylist ? 0 : playlist.count - items.count
            selectItemForInspection(at: index)
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

            return enumerator.compactMap { item in
                guard let fileURL = item as? URL else { return nil }
                return isSupportedMedia(fileURL) ? fileURL : nil
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }

        return isSupportedMedia(url) ? [url] : []
    }

    private func isSupportedMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    private func isSubtitleFile(_ url: URL) -> Bool {
        url.isFileURL && subtitleExtensions.contains(url.pathExtension.lowercased())
    }

    private func playItem(at index: Int) {
        saveCurrentPosition()
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        savePlaylistState()
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)

        let item = playlist[index]
        stateStore.addRecentMedia(item)
        updateMetadata(for: item)
        updateNowPlaying(title: item.title, detail: item.subtitle)
        let resumeTime = promptedResumeTime(for: item)

        if shouldUseVLC(for: item) {
            playWithVLC(item, resumeTime: resumeTime)
        } else if shouldUseMPV(for: item) {
            playWithMPV(item, resumeTime: resumeTime)
        } else {
            playNatively(item, fallbackToMPV: true, resumeTime: resumeTime)
        }

        refreshControls()
    }

    private func playNatively(_ item: MediaItem, fallbackToMPV: Bool, resumeTime: Double?) {
        codecTimer?.invalidate()
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
        engineLabel.stringValue = "Playing in-app with AVFoundation"
    }

    private func playWithVLC(_ item: MediaItem, resumeTime: Double?) {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        mpvBridge.stop()
        itemStatusObservation = nil
        codecTimer?.invalidate()
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
            currentEngine = .none
            vlcVideoSurface.isHidden = true
            playerView.isHidden = false
            engineLabel.stringValue = error.localizedDescription
        }
    }

    private func playWithMPV(_ item: MediaItem, resumeTime: Double?) {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        vlcBridge.stop()
        itemStatusObservation = nil
        codecTimer?.invalidate()
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
        } catch {
            currentEngine = .none
            engineLabel.stringValue = error.localizedDescription
            playerView.isHidden = false
        }
    }

    private func shouldUseVLC(for item: MediaItem) -> Bool {
        vlcBridge.isAvailable
    }

    private func shouldUseMPV(for item: MediaItem) -> Bool {
        (item.isNetworkStream || !nativeExtensions.contains(item.fileExtension)) && mpvBridge.isAvailable
    }

    private func handleNativeFailure(for item: MediaItem, fallbackToMPV: Bool, error: Error?) {
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
        engineLabel.stringValue = "\(message) Install VLC or mpv for VLC-like codec coverage and 200% volume boost."
        refreshControls()
    }

    private func stopPlayback() {
        saveCurrentPosition()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        codecTimer?.invalidate()
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
        updateSidebarButton(sidebarHidden: sidebarView?.isHidden == true)
        updateEmptyState()
    }

    private func updateSidebarButton(sidebarHidden: Bool) {
        sidebarButton.image = NSImage(
            systemSymbolName: sidebarHidden ? "sidebar.left" : "sidebar.left",
            accessibilityDescription: sidebarHidden ? "Show sidebar" : "Hide sidebar"
        )
        sidebarButton.toolTip = sidebarHidden ? "Show sidebar" : "Hide sidebar"
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !playlist.isEmpty || currentEngine != .none
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

        let restored = stateStore.loadPlaylist()
        playlist = restored.0
        if let index = restored.1, playlist.indices.contains(index) {
            currentIndex = index
        }

        tableView.reloadData()
        if let currentIndex {
            tableView.selectRowIndexes(IndexSet(integer: currentIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(currentIndex)
            let item = playlist[currentIndex]
            updateNowPlaying(title: item.title, detail: "Restored playlist")
            updateMetadata(for: item)
        }
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
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        let item = playlist[index]
        updateMetadata(for: item)
        updateNowPlaying(title: item.title, detail: "Ready to play")
        savePlaylistState()
    }

    private func updateMetadataForSelection() {
        let row = tableView.selectedRow
        guard playlist.indices.contains(row) else {
            metadataRequestID += 1
            metadataTextView.stringValue = "Select a media item to inspect it before playback."
            return
        }
        updateMetadata(for: playlist[row])
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
                self.metadataTextView.stringValue = """
                \(metadata.title)

                Type: \(metadata.kind)
                Size: \(metadata.size)
                Duration: \(metadata.duration)
                Video: \(metadata.dimensions)
                Modified: \(metadata.modified)
                Resume: \(metadata.savedPosition)

                \(metadata.location)
                \(extraDetails)
                """
            }
        }
    }

    private var currentItem: MediaItem? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
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
        guard sender.clickedRow >= 0 else { return }
        playItem(at: sender.clickedRow)
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
        playlist.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if currentEngine == .none {
            let row = tableView.selectedRow
            if playlist.indices.contains(row) {
                currentIndex = row
                updateNowPlaying(title: playlist[row].title, detail: "Ready to play")
                savePlaylistState()
            }
        }
        updateMetadataForSelection()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MediaCell")
        let item = playlist[row]
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
        guard notification.object as? NSPanel === videoAdjustmentPanel else { return }
        videoAdjustmentPanel = nil
        videoAdjustmentSliders = [:]
    }
}

private enum PlaybackEngine {
    case none
    case native
    case vlc
    case mpv
}
