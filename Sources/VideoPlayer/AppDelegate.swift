import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var playerWindowController: PlayerWindowController?
    private let openRecentMenu = NSMenu(title: "Open Recent")
    private let chaptersMenu = NSMenu(title: "Chapters")
    private let audioOutputMenu = NSMenu(title: "Audio Output")
    private let updateChecker = UpdateChecker()

    private var playerViewController: PlayerViewController? {
        playerWindowController?.playerViewController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PlayerWindowController()
        playerWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        buildMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        playerWindowController?.playerViewController.openMedia(urls, replacePlaylist: true)
    }

    @objc private func openDocument(_ sender: Any?) {
        playerViewController?.openFilesPanel(replacePlaylist: true)
    }

    @objc private func addToPlaylist(_ sender: Any?) {
        playerViewController?.openFilesPanel(replacePlaylist: false)
    }

    @objc private func openNetworkStream(_ sender: Any?) {
        playerViewController?.openNetworkStreamDialog(sender)
    }

    @objc private func openRecentItem(_ sender: NSMenuItem) {
        playerViewController?.openRecentMedia(at: sender.tag)
    }

    @objc private func clearRecentMedia(_ sender: Any?) {
        playerViewController?.clearRecentMedia()
    }

    @objc private func addLibraryFolder(_ sender: Any?) {
        playerViewController?.chooseLibraryFolder(sender)
    }

    @objc private func loadLibraryFolders(_ sender: Any?) {
        playerViewController?.loadLibraryFolders(sender)
    }

    @objc private func loadSubtitle(_ sender: Any?) {
        playerViewController?.openSubtitlePanel(sender)
    }

    @objc private func togglePlayback(_ sender: Any?) {
        playerViewController?.togglePlayPause(sender)
    }

    @objc private func seekBackward(_ sender: Any?) {
        playerViewController?.seekBackward(sender)
    }

    @objc private func seekForward(_ sender: Any?) {
        playerViewController?.seekForward(sender)
    }

    @objc private func playPrevious(_ sender: Any?) {
        playerViewController?.playPrevious(sender)
    }

    @objc private func playNext(_ sender: Any?) {
        playerViewController?.playNext(sender)
    }

    @objc private func volumeUp(_ sender: Any?) {
        playerViewController?.volumeUp(sender)
    }

    @objc private func volumeDown(_ sender: Any?) {
        playerViewController?.volumeDown(sender)
    }

    @objc private func toggleMute(_ sender: Any?) {
        playerViewController?.toggleMute(sender)
    }

    @objc private func takeScreenshot(_ sender: Any?) {
        playerViewController?.takeScreenshot(sender)
    }

    @objc private func setLoopStart(_ sender: Any?) {
        playerViewController?.setLoopStart(sender)
    }

    @objc private func setLoopEnd(_ sender: Any?) {
        playerViewController?.setLoopEnd(sender)
    }

    @objc private func clearLoop(_ sender: Any?) {
        playerViewController?.clearLoop(sender)
    }

    @objc private func applyAudioPreset(_ sender: NSMenuItem) {
        let presetName = (sender.representedObject as? String) ?? sender.title
        playerViewController?.applyAudioPreset(named: presetName)
    }

    @objc private func previousChapter(_ sender: Any?) {
        playerViewController?.previousChapter(sender)
    }

    @objc private func nextChapter(_ sender: Any?) {
        playerViewController?.nextChapter(sender)
    }

    @objc private func selectChapter(_ sender: NSMenuItem) {
        playerViewController?.selectChapter(at: sender.tag)
    }

    @objc private func decreaseAudioDelay(_ sender: Any?) {
        playerViewController?.decreaseAudioDelay(sender)
    }

    @objc private func increaseAudioDelay(_ sender: Any?) {
        playerViewController?.increaseAudioDelay(sender)
    }

    @objc private func resetAudioDelay(_ sender: Any?) {
        playerViewController?.resetAudioDelay(sender)
    }

    @objc private func selectAudioOutput(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        playerViewController?.selectAudioOutputDevice(id: id, name: sender.title)
    }

    @objc private func showVideoAdjustments(_ sender: Any?) {
        playerViewController?.showVideoAdjustments(sender)
    }

    @objc private func resetVideoAdjustments(_ sender: Any?) {
        playerViewController?.resetVideoAdjustments(sender)
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        playerViewController?.toggleSidebar(sender)
    }

    @objc private func toggleMiniPlayer(_ sender: Any?) {
        playerViewController?.toggleMiniPlayer(sender)
    }

    @objc private func togglePictureInPicture(_ sender: Any?) {
        playerViewController?.togglePictureInPicture(sender)
    }

    @objc private func toggleTheaterMode(_ sender: Any?) {
        playerViewController?.toggleTheaterMode(sender)
    }

    @objc private func toggleFullscreen(_ sender: Any?) {
        playerWindowController?.window?.toggleFullScreen(sender)
    }

    @objc private func showAbout(_ sender: Any?) {
        showTextDialog(title: "About Video Player", text: OpenSourceNotices.aboutText, height: 220)
    }

    @objc private func showOpenSourceLicenses(_ sender: Any?) {
        showTextDialog(title: "Open Source Licenses", text: OpenSourceNotices.licenseText, height: 420)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateChecker.checkForUpdates(presentingWindow: playerWindowController?.window)
    }

    @objc private func openProjectRepository(_ sender: Any?) {
        NSWorkspace.shared.open(OpenSourceNotices.repositoryURL)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === openRecentMenu {
            rebuildOpenRecentMenu()
        } else if menu === chaptersMenu {
            rebuildChaptersMenu()
        } else if menu === audioOutputMenu {
            rebuildAudioOutputMenu()
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu(title: "Video Player")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Video Player")
        let aboutItem = NSMenuItem(title: "About Video Player", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        let licensesItem = NSMenuItem(title: "Open Source Licenses", action: #selector(showOpenSourceLicenses(_:)), keyEquivalent: "")
        licensesItem.target = self
        appMenu.addItem(licensesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Video Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        let addItem = NSMenuItem(title: "Add to Playlist...", action: #selector(addToPlaylist(_:)), keyEquivalent: "O")
        addItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(addItem)

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        openRecentMenu.delegate = self
        recentItem.submenu = openRecentMenu
        fileMenu.addItem(recentItem)

        let networkItem = NSMenuItem(title: "Open Network Stream...", action: #selector(openNetworkStream(_:)), keyEquivalent: "n")
        networkItem.target = self
        fileMenu.addItem(networkItem)
        fileMenu.addItem(.separator())
        let addLibraryItem = NSMenuItem(title: "Add Library Folder...", action: #selector(addLibraryFolder(_:)), keyEquivalent: "l")
        addLibraryItem.keyEquivalentModifierMask = [.command, .option]
        addLibraryItem.target = self
        fileMenu.addItem(addLibraryItem)
        let loadLibraryItem = NSMenuItem(title: "Load Library Folders", action: #selector(loadLibraryFolders(_:)), keyEquivalent: "l")
        loadLibraryItem.target = self
        fileMenu.addItem(loadLibraryItem)
        fileMenu.addItem(.separator())
        let subtitleItem = NSMenuItem(title: "Load Subtitle...", action: #selector(loadSubtitle(_:)), keyEquivalent: "s")
        subtitleItem.target = self
        fileMenu.addItem(subtitleItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let playbackMenuItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenu.addItem(NSMenuItem(title: "Play/Pause", action: #selector(togglePlayback(_:)), keyEquivalent: " "))
        playbackMenu.addItem(NSMenuItem(title: "Back 10 Seconds", action: #selector(seekBackward(_:)), keyEquivalent: "\u{2190}"))
        playbackMenu.addItem(NSMenuItem(title: "Forward 10 Seconds", action: #selector(seekForward(_:)), keyEquivalent: "\u{2192}"))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(NSMenuItem(title: "Previous Item", action: #selector(playPrevious(_:)), keyEquivalent: "["))
        playbackMenu.addItem(NSMenuItem(title: "Next Item", action: #selector(playNext(_:)), keyEquivalent: "]"))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(NSMenuItem(title: "Volume Up", action: #selector(volumeUp(_:)), keyEquivalent: "\u{2191}"))
        playbackMenu.addItem(NSMenuItem(title: "Volume Down", action: #selector(volumeDown(_:)), keyEquivalent: "\u{2193}"))
        playbackMenu.addItem(NSMenuItem(title: "Mute", action: #selector(toggleMute(_:)), keyEquivalent: "m"))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot(_:)), keyEquivalent: "p"))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(NSMenuItem(title: "Previous Chapter", action: #selector(previousChapter(_:)), keyEquivalent: ","))
        playbackMenu.addItem(NSMenuItem(title: "Next Chapter", action: #selector(nextChapter(_:)), keyEquivalent: "."))
        let chaptersItem = NSMenuItem(title: "Chapters", action: nil, keyEquivalent: "")
        chaptersMenu.delegate = self
        chaptersItem.submenu = chaptersMenu
        playbackMenu.addItem(chaptersItem)
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(NSMenuItem(title: "Set Loop Start", action: #selector(setLoopStart(_:)), keyEquivalent: "a"))
        playbackMenu.addItem(NSMenuItem(title: "Set Loop End", action: #selector(setLoopEnd(_:)), keyEquivalent: "b"))
        let clearLoopItem = NSMenuItem(title: "Clear Loop", action: #selector(clearLoop(_:)), keyEquivalent: "b")
        clearLoopItem.keyEquivalentModifierMask = [.command, .shift]
        playbackMenu.addItem(clearLoopItem)
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(makeAudioPresetMenuItem())
        let audioOutputItem = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        audioOutputMenu.delegate = self
        audioOutputItem.submenu = audioOutputMenu
        playbackMenu.addItem(audioOutputItem)
        playbackMenu.addItem(NSMenuItem(title: "Audio Delay -0.1s", action: #selector(decreaseAudioDelay(_:)), keyEquivalent: "{"))
        playbackMenu.addItem(NSMenuItem(title: "Audio Delay +0.1s", action: #selector(increaseAudioDelay(_:)), keyEquivalent: "}"))
        playbackMenu.addItem(NSMenuItem(title: "Reset Audio Delay", action: #selector(resetAudioDelay(_:)), keyEquivalent: "\\"))
        playbackMenu.items.forEach { $0.target = self }
        playbackMenuItem.submenu = playbackMenu
        mainMenu.addItem(playbackMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let miniItem = NSMenuItem(title: "Mini Player", action: #selector(toggleMiniPlayer(_:)), keyEquivalent: "m")
        miniItem.keyEquivalentModifierMask = [.command, .option]
        miniItem.target = self
        viewMenu.addItem(miniItem)
        let pipItem = NSMenuItem(title: "Picture in Picture", action: #selector(togglePictureInPicture(_:)), keyEquivalent: "p")
        pipItem.keyEquivalentModifierMask = [.command, .option]
        pipItem.target = self
        viewMenu.addItem(pipItem)
        let theaterItem = NSMenuItem(title: "Theater Mode", action: #selector(toggleTheaterMode(_:)), keyEquivalent: "t")
        theaterItem.keyEquivalentModifierMask = [.command, .option]
        theaterItem.target = self
        viewMenu.addItem(theaterItem)
        viewMenu.addItem(.separator())
        let videoAdjustmentsItem = NSMenuItem(title: "Video Adjustments...", action: #selector(showVideoAdjustments(_:)), keyEquivalent: "e")
        videoAdjustmentsItem.keyEquivalentModifierMask = [.command, .option]
        videoAdjustmentsItem.target = self
        viewMenu.addItem(videoAdjustmentsItem)
        let resetVideoItem = NSMenuItem(title: "Reset Video Adjustments", action: #selector(resetVideoAdjustments(_:)), keyEquivalent: "e")
        resetVideoItem.keyEquivalentModifierMask = [.command, .option, .shift]
        resetVideoItem.target = self
        viewMenu.addItem(resetVideoItem)
        viewMenu.addItem(.separator())
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .option]
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)
        viewMenu.addItem(.separator())
        let fullscreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(toggleFullscreen(_:)), keyEquivalent: "f")
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenItem.target = self
        viewMenu.addItem(fullscreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let helpUpdateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        helpUpdateItem.target = self
        helpMenu.addItem(helpUpdateItem)
        let helpLicensesItem = NSMenuItem(title: "Open Source Licenses", action: #selector(showOpenSourceLicenses(_:)), keyEquivalent: "")
        helpLicensesItem.target = self
        helpMenu.addItem(helpLicensesItem)
        helpMenu.addItem(.separator())
        let repositoryItem = NSMenuItem(title: "Project on GitHub", action: #selector(openProjectRepository(_:)), keyEquivalent: "")
        repositoryItem.target = self
        helpMenu.addItem(repositoryItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApplication.shared.helpMenu = helpMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private func rebuildOpenRecentMenu() {
        openRecentMenu.removeAllItems()
        let items = playerViewController?.recentMediaItems() ?? []

        guard !items.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Recent Media", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openRecentMenu.addItem(emptyItem)
            return
        }

        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(openRecentItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = index
            menuItem.toolTip = item.isNetworkStream ? item.url.absoluteString : item.url.path
            openRecentMenu.addItem(menuItem)
        }

        openRecentMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentMedia(_:)), keyEquivalent: "")
        clearItem.target = self
        openRecentMenu.addItem(clearItem)
    }

    private func makeAudioPresetMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Audio Preset")
        for preset in AudioPreset.allCases {
            let item = NSMenuItem(title: preset.rawValue, action: #selector(applyAudioPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            menu.addItem(item)
        }

        let parent = NSMenuItem(title: "Audio Preset", action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    private func rebuildChaptersMenu() {
        chaptersMenu.removeAllItems()
        let chapters = playerViewController?.chapterItems() ?? []

        guard !chapters.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Chapters", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            chaptersMenu.addItem(emptyItem)
            return
        }

        for (index, chapter) in chapters.enumerated() {
            let title = "\(formatTime(chapter.startTime))  \(chapter.name)"
            let item = NSMenuItem(title: title, action: #selector(selectChapter(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            chaptersMenu.addItem(item)
        }
    }

    private func rebuildAudioOutputMenu() {
        audioOutputMenu.removeAllItems()
        let devices = playerViewController?.audioOutputDevices() ?? []

        guard !devices.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Devices Found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            audioOutputMenu.addItem(emptyItem)
            return
        }

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectAudioOutput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            audioOutputMenu.addItem(item)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func showTextDialog(title: String, text: String, height: CGFloat) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: height))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.runModal()
    }
}
