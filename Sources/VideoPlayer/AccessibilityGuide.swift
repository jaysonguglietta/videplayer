import Foundation

enum AccessibilityGuide {
    static let text = """
    Keyboard Shortcuts and Accessibility
    ====================================

    Playback
    - Space or K: play/pause
    - Left arrow or J: rewind 10 seconds
    - Right arrow or L: fast-forward 10 seconds
    - Up arrow: volume up
    - Down arrow: volume down
    - M: mute
    - F: full screen
    - B: show or hide the sidebar
    - [ and ]: previous or next playlist item

    Playlist
    - Delete: remove selected playlist rows
    - Double-click a row: play selected media
    - Search field: filter by title, extension, path, or stream URL

    Enterprise and Support
    - Help > Playback Diagnostics: explain codec routing and next action
    - Help > Playback Engine Doctor: inspect VLC/mpv trust state
    - Help > Export Support Bundle: export redacted support evidence
    - Help > Enterprise Status: show managed policy and license state

    Accessibility Notes
    - Core controls expose VoiceOver labels and help text.
    - Dialog reports use selectable text for screen readers and support copy/paste.
    - Kiosk deployments should preconfigure playlists and approved stream hosts so users do not need file browsing.
    """
}
