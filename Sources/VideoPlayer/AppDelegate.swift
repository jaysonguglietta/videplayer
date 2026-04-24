import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var playerWindowController: PlayerWindowController?

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
        playerWindowController?.playerViewController.openFilesPanel(replacePlaylist: true)
    }

    @objc private func addToPlaylist(_ sender: Any?) {
        playerWindowController?.playerViewController.openFilesPanel(replacePlaylist: false)
    }

    @objc private func openNetworkStream(_ sender: Any?) {
        playerWindowController?.playerViewController.openNetworkStreamDialog(sender)
    }

    @objc private func loadSubtitle(_ sender: Any?) {
        playerWindowController?.playerViewController.openSubtitlePanel(sender)
    }

    @objc private func togglePlayback(_ sender: Any?) {
        playerWindowController?.playerViewController.togglePlayPause(sender)
    }

    @objc private func seekBackward(_ sender: Any?) {
        playerWindowController?.playerViewController.seekBackward(sender)
    }

    @objc private func seekForward(_ sender: Any?) {
        playerWindowController?.playerViewController.seekForward(sender)
    }

    @objc private func playPrevious(_ sender: Any?) {
        playerWindowController?.playerViewController.playPrevious(sender)
    }

    @objc private func playNext(_ sender: Any?) {
        playerWindowController?.playerViewController.playNext(sender)
    }

    @objc private func volumeUp(_ sender: Any?) {
        playerWindowController?.playerViewController.volumeUp(sender)
    }

    @objc private func volumeDown(_ sender: Any?) {
        playerWindowController?.playerViewController.volumeDown(sender)
    }

    @objc private func toggleMute(_ sender: Any?) {
        playerWindowController?.playerViewController.toggleMute(sender)
    }

    @objc private func toggleFullscreen(_ sender: Any?) {
        playerWindowController?.window?.toggleFullScreen(sender)
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
        let networkItem = NSMenuItem(title: "Open Network Stream...", action: #selector(openNetworkStream(_:)), keyEquivalent: "n")
        networkItem.target = self
        fileMenu.addItem(networkItem)
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
        playbackMenu.items.forEach { $0.target = self }
        playbackMenuItem.submenu = playbackMenu
        mainMenu.addItem(playbackMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullscreenItem = NSMenuItem(title: "Enter Full Screen", action: #selector(toggleFullscreen(_:)), keyEquivalent: "f")
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenItem.target = self
        viewMenu.addItem(fullscreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }
}
