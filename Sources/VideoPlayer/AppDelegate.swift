import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var playerWindowController: PlayerWindowController?
    private let openRecentMenu = NSMenu(title: "Open Recent")

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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openRecentMenu else { return }
        rebuildOpenRecentMenu()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu(title: "Video Player")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Video Player")
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
        playbackMenu.addItem(NSMenuItem(title: "Set Loop Start", action: #selector(setLoopStart(_:)), keyEquivalent: "a"))
        playbackMenu.addItem(NSMenuItem(title: "Set Loop End", action: #selector(setLoopEnd(_:)), keyEquivalent: "b"))
        let clearLoopItem = NSMenuItem(title: "Clear Loop", action: #selector(clearLoop(_:)), keyEquivalent: "b")
        clearLoopItem.keyEquivalentModifierMask = [.command, .shift]
        playbackMenu.addItem(clearLoopItem)
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(makeAudioPresetMenuItem())
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
}
