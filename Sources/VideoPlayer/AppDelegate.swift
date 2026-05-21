import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var playerWindowController: PlayerWindowController?
    private let openRecentMenu = NSMenu(title: "Open Recent")
    private let chaptersMenu = NSMenu(title: "Chapters")
    private let audioOutputMenu = NSMenu(title: "Audio Output")
    private let updateChecker = UpdateChecker()
    private var externalEnginesMenuItem: NSMenuItem?
    private var privateStreamsMenuItem: NSMenuItem?
    private var saveHistoryMenuItem: NSMenuItem?
    private var clearHistoryOnQuitMenuItem: NSMenuItem?
    private var pendingOpenURLs: [URL] = []

    private var playerViewController: PlayerViewController? {
        playerWindowController?.playerViewController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("Application launched version=\(OpenSourceNotices.appVersion) log=\(AppLogger.logFileURL.path)", flush: true)
        HangWatchdog.start()
        let controller = PlayerWindowController()
        playerWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        buildMainMenu()
        openPendingURLsIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLogger.info("Application requested to open \(urls.count) URL(s): \(urls.map(\.lastPathComponent).joined(separator: ", "))")
        guard let playerViewController else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        playerViewController.openMedia(urls, replacePlaylist: true)
    }

    private func openPendingURLsIfNeeded() {
        guard !pendingOpenURLs.isEmpty, let playerViewController else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        playerViewController.openMedia(urls, replacePlaylist: true)
    }

    @objc private func openDocument(_ sender: Any?) {
        playerViewController?.openFilesPanel(replacePlaylist: true)
    }

    @objc private func addToPlaylist(_ sender: Any?) {
        playerViewController?.openFilesPanel(replacePlaylist: false)
    }

    @objc private func importPlaylist(_ sender: Any?) {
        playerViewController?.importPlaylistPanel(sender)
    }

    @objc private func exportPlaylist(_ sender: Any?) {
        playerViewController?.exportPlaylistPanel(sender)
    }

    @objc private func removeSelectedFromPlaylist(_ sender: Any?) {
        playerViewController?.removeSelectedPlaylistItems(sender)
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

    @objc private func manageLibraryFolders(_ sender: Any?) {
        playerViewController?.showLibraryManager(sender)
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

    @objc private func toggleExternalMediaEngines(_ sender: Any?) {
        playerViewController?.toggleExternalMediaEngines(sender)
        updateSecurityMenuStates()
    }

    @objc private func togglePrivateNetworkStreams(_ sender: Any?) {
        playerViewController?.togglePrivateNetworkStreams(sender)
        updateSecurityMenuStates()
    }

    @objc private func toggleSavePlaybackHistory(_ sender: Any?) {
        playerViewController?.toggleSavePlaybackHistory(sender)
        updateSecurityMenuStates()
    }

    @objc private func toggleClearHistoryOnQuit(_ sender: Any?) {
        playerViewController?.toggleClearHistoryOnQuit(sender)
        updateSecurityMenuStates()
    }

    @objc private func clearAllPlaybackHistory(_ sender: Any?) {
        playerViewController?.clearAllPlaybackHistory(sender)
    }

    @objc private func showAbout(_ sender: Any?) {
        showTextDialog(title: "About Video Player", text: OpenSourceNotices.aboutText, height: 220)
    }

    @objc private func showOpenSourceLicenses(_ sender: Any?) {
        showTextDialog(title: "Open Source Licenses", text: OpenSourceNotices.licenseText, height: 420)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        let policy = EnterprisePolicy.snapshot()
        guard !policy.disableUpdateChecks else {
            AppLogger.info("Update check blocked by enterprise policy", flush: true)
            showTextDialog(
                title: "Updates Managed by Your Organization",
                text: "Update checks are disabled by enterprise policy. Contact your administrator for deployment updates.",
                height: 120
            )
            return
        }
        AppLogger.info("User requested update check")
        updateChecker.checkForUpdates(presentingWindow: playerWindowController?.window)
    }

    @objc private func showEnterpriseStatus(_ sender: Any?) {
        playerViewController?.showEnterpriseStatus(sender)
    }

    @objc private func showReleaseReadiness(_ sender: Any?) {
        playerViewController?.showReleaseReadiness(sender)
    }

    @objc private func showMediaEngineDoctor(_ sender: Any?) {
        playerViewController?.showMediaEngineDoctor(sender)
    }

    @objc private func exportMDMPolicyProfile(_ sender: Any?) {
        playerViewController?.exportMDMPolicyProfile(sender)
    }

    @objc private func showPlaybackDiagnostics(_ sender: Any?) {
        playerViewController?.showPlaybackDiagnostics(sender)
    }

    @objc private func exportSupportBundle(_ sender: Any?) {
        playerViewController?.exportSupportBundle(sender)
    }

    @objc private func showLicenseStatus(_ sender: Any?) {
        playerViewController?.showLicenseStatus(sender)
    }

    @objc private func importLicense(_ sender: Any?) {
        playerViewController?.importEnterpriseLicense(sender)
    }

    @objc private func createActivationRequest(_ sender: Any?) {
        playerViewController?.createEnterpriseActivationRequest(sender)
    }

    @objc private func deactivateLicense(_ sender: Any?) {
        playerViewController?.deactivateEnterpriseLicense(sender)
    }

    @objc private func showAccessibilityGuide(_ sender: Any?) {
        playerViewController?.showAccessibilityGuide(sender)
    }

    @objc private func showLibraryReport(_ sender: Any?) {
        playerViewController?.showLibraryReport(sender)
    }

    @objc private func toggleFavorite(_ sender: Any?) {
        playerViewController?.toggleFavoriteForSelectedItems(sender)
    }

    @objc private func markWatched(_ sender: Any?) {
        playerViewController?.setWatchedForSelectedItems(true, sender: sender)
    }

    @objc private func markUnwatched(_ sender: Any?) {
        playerViewController?.setWatchedForSelectedItems(false, sender: sender)
    }

    @objc private func setTags(_ sender: Any?) {
        playerViewController?.setTagsForSelectedItem(sender)
    }

    @objc private func openProjectRepository(_ sender: Any?) {
        NSWorkspace.shared.open(OpenSourceNotices.repositoryURL)
    }

    @objc private func revealLogFile(_ sender: Any?) {
        let logURL = AppLogger.ensureLogFile()
        AppLogger.info("User revealed log file at \(logURL.path)", flush: true)
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === openRecentMenu {
            rebuildOpenRecentMenu()
        } else if menu === chaptersMenu {
            rebuildChaptersMenu()
        } else if menu === audioOutputMenu {
            rebuildAudioOutputMenu()
        }
        updateSecurityMenuStates()
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
        let logItem = NSMenuItem(title: "Reveal Log File", action: #selector(revealLogFile(_:)), keyEquivalent: "")
        logItem.target = self
        appMenu.addItem(logItem)
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
        fileMenu.addItem(.separator())
        let importPlaylistItem = NSMenuItem(title: "Import Playlist...", action: #selector(importPlaylist(_:)), keyEquivalent: "")
        importPlaylistItem.target = self
        fileMenu.addItem(importPlaylistItem)
        let exportPlaylistItem = NSMenuItem(title: "Export Playlist...", action: #selector(exportPlaylist(_:)), keyEquivalent: "")
        exportPlaylistItem.target = self
        fileMenu.addItem(exportPlaylistItem)
        fileMenu.addItem(.separator())
        let removeSelectedItem = NSMenuItem(title: "Remove Selected from Playlist", action: #selector(removeSelectedFromPlaylist(_:)), keyEquivalent: "")
        removeSelectedItem.target = self
        fileMenu.addItem(removeSelectedItem)

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
        let manageLibraryItem = NSMenuItem(title: "Manage Library Folders...", action: #selector(manageLibraryFolders(_:)), keyEquivalent: "")
        manageLibraryItem.target = self
        fileMenu.addItem(manageLibraryItem)
        let libraryReportItem = NSMenuItem(title: "Library Report...", action: #selector(showLibraryReport(_:)), keyEquivalent: "")
        libraryReportItem.target = self
        fileMenu.addItem(libraryReportItem)
        fileMenu.addItem(.separator())
        let favoriteItem = NSMenuItem(title: "Toggle Favorite", action: #selector(toggleFavorite(_:)), keyEquivalent: "")
        favoriteItem.target = self
        fileMenu.addItem(favoriteItem)
        let watchedItem = NSMenuItem(title: "Mark Watched", action: #selector(markWatched(_:)), keyEquivalent: "")
        watchedItem.target = self
        fileMenu.addItem(watchedItem)
        let unwatchedItem = NSMenuItem(title: "Mark Unwatched", action: #selector(markUnwatched(_:)), keyEquivalent: "")
        unwatchedItem.target = self
        fileMenu.addItem(unwatchedItem)
        let tagsItem = NSMenuItem(title: "Set Tags...", action: #selector(setTags(_:)), keyEquivalent: "")
        tagsItem.target = self
        fileMenu.addItem(tagsItem)
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
        playbackMenu.addItem(.separator())
        let externalEnginesItem = NSMenuItem(title: "Enable External VLC/mpv Engines", action: #selector(toggleExternalMediaEngines(_:)), keyEquivalent: "")
        externalEnginesItem.target = self
        playbackMenu.addItem(externalEnginesItem)
        self.externalEnginesMenuItem = externalEnginesItem
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

        let privacyMenuItem = NSMenuItem()
        let privacyMenu = NSMenu(title: "Privacy")
        let saveHistoryItem = NSMenuItem(title: "Save Playback History", action: #selector(toggleSavePlaybackHistory(_:)), keyEquivalent: "")
        saveHistoryItem.target = self
        privacyMenu.addItem(saveHistoryItem)
        self.saveHistoryMenuItem = saveHistoryItem
        let clearOnQuitItem = NSMenuItem(title: "Clear History on Quit", action: #selector(toggleClearHistoryOnQuit(_:)), keyEquivalent: "")
        clearOnQuitItem.target = self
        privacyMenu.addItem(clearOnQuitItem)
        self.clearHistoryOnQuitMenuItem = clearOnQuitItem
        privacyMenu.addItem(.separator())
        let clearHistoryItem = NSMenuItem(title: "Clear All Playback History", action: #selector(clearAllPlaybackHistory(_:)), keyEquivalent: "")
        clearHistoryItem.target = self
        privacyMenu.addItem(clearHistoryItem)
        privacyMenu.addItem(.separator())
        let privateStreamsItem = NSMenuItem(title: "Allow Private Network Streams", action: #selector(togglePrivateNetworkStreams(_:)), keyEquivalent: "")
        privateStreamsItem.target = self
        privacyMenu.addItem(privateStreamsItem)
        self.privateStreamsMenuItem = privateStreamsItem
        privacyMenuItem.submenu = privacyMenu
        mainMenu.addItem(privacyMenuItem)

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let helpUpdateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        helpUpdateItem.target = self
        helpMenu.addItem(helpUpdateItem)
        let diagnosticsItem = NSMenuItem(title: "Playback Diagnostics...", action: #selector(showPlaybackDiagnostics(_:)), keyEquivalent: "")
        diagnosticsItem.target = self
        helpMenu.addItem(diagnosticsItem)
        let engineDoctorItem = NSMenuItem(title: "Playback Engine Doctor...", action: #selector(showMediaEngineDoctor(_:)), keyEquivalent: "")
        engineDoctorItem.target = self
        helpMenu.addItem(engineDoctorItem)
        let releaseReadinessItem = NSMenuItem(title: "Release Readiness...", action: #selector(showReleaseReadiness(_:)), keyEquivalent: "")
        releaseReadinessItem.target = self
        helpMenu.addItem(releaseReadinessItem)
        let enterpriseStatusItem = NSMenuItem(title: "Enterprise Status...", action: #selector(showEnterpriseStatus(_:)), keyEquivalent: "")
        enterpriseStatusItem.target = self
        helpMenu.addItem(enterpriseStatusItem)
        let mdmProfileItem = NSMenuItem(title: "Export MDM Policy Profile...", action: #selector(exportMDMPolicyProfile(_:)), keyEquivalent: "")
        mdmProfileItem.target = self
        helpMenu.addItem(mdmProfileItem)
        let supportBundleItem = NSMenuItem(title: "Export Support Bundle...", action: #selector(exportSupportBundle(_:)), keyEquivalent: "")
        supportBundleItem.target = self
        helpMenu.addItem(supportBundleItem)
        helpMenu.addItem(.separator())
        let licenseStatusItem = NSMenuItem(title: "License Status...", action: #selector(showLicenseStatus(_:)), keyEquivalent: "")
        licenseStatusItem.target = self
        helpMenu.addItem(licenseStatusItem)
        let importLicenseItem = NSMenuItem(title: "Import Enterprise License...", action: #selector(importLicense(_:)), keyEquivalent: "")
        importLicenseItem.target = self
        helpMenu.addItem(importLicenseItem)
        let activationItem = NSMenuItem(title: "Create License Activation Request...", action: #selector(createActivationRequest(_:)), keyEquivalent: "")
        activationItem.target = self
        helpMenu.addItem(activationItem)
        let deactivateItem = NSMenuItem(title: "Deactivate Enterprise License", action: #selector(deactivateLicense(_:)), keyEquivalent: "")
        deactivateItem.target = self
        helpMenu.addItem(deactivateItem)
        helpMenu.addItem(.separator())
        let accessibilityItem = NSMenuItem(title: "Keyboard Shortcuts and Accessibility...", action: #selector(showAccessibilityGuide(_:)), keyEquivalent: "")
        accessibilityItem.target = self
        helpMenu.addItem(accessibilityItem)
        helpMenu.addItem(.separator())
        let helpLicensesItem = NSMenuItem(title: "Open Source Licenses", action: #selector(showOpenSourceLicenses(_:)), keyEquivalent: "")
        helpLicensesItem.target = self
        helpMenu.addItem(helpLicensesItem)
        let helpLogItem = NSMenuItem(title: "Reveal Log File", action: #selector(revealLogFile(_:)), keyEquivalent: "")
        helpLogItem.target = self
        helpMenu.addItem(helpLogItem)
        helpMenu.addItem(.separator())
        let repositoryItem = NSMenuItem(title: "Project on GitHub", action: #selector(openProjectRepository(_:)), keyEquivalent: "")
        repositoryItem.target = self
        helpMenu.addItem(repositoryItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApplication.shared.helpMenu = helpMenu

        NSApplication.shared.mainMenu = mainMenu
        updateSecurityMenuStates()
    }

    private func updateSecurityMenuStates() {
        let policy = EnterprisePolicy.snapshot()
        externalEnginesMenuItem?.state = playerViewController?.externalMediaEnginesEnabled() == true ? .on : .off
        externalEnginesMenuItem?.isEnabled = playerViewController?.externalMediaEnginesAvailable() == true
            && !policy.forceDisableExternalMediaEngines
        privateStreamsMenuItem?.state = playerViewController?.privateNetworkStreamsEnabled() == true ? .on : .off
        privateStreamsMenuItem?.isEnabled = !policy.forceBlockPrivateNetworkStreams
        saveHistoryMenuItem?.state = playerViewController?.savePlaybackHistoryEnabled() == true ? .on : .off
        saveHistoryMenuItem?.isEnabled = !policy.forceDisablePlaybackHistory
        clearHistoryOnQuitMenuItem?.state = playerViewController?.clearHistoryOnQuitEnabled() == true ? .on : .off
        clearHistoryOnQuitMenuItem?.isEnabled = !policy.forceClearHistoryOnQuit
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
