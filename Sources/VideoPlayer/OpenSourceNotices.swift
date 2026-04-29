import Foundation

enum OpenSourceNotices {
    static let repositoryURL = URL(string: "https://github.com/jaysonguglietta/videplayer")!

    static var aboutText: String {
        """
        Video Player
        Version \(appVersion)

        A native macOS media player inspired by VLC, with LibVLC-backed playback for broad codec support.

        Repository:
        \(repositoryURL.absoluteString)

        License:
        MIT License
        """
    }

    static var licenseText: String {
        """
        Open Source Software and Licenses

        Video Player
        - Local application code in this repository.
        - Project license: MIT License.
        - Copyright (c) 2026 Jayson Guglietta.
        - License file: LICENSE in the repository root.
        - Repository: \(repositoryURL.absoluteString)

        VideoLAN VLC / libVLC
        - Used for broad codec playback, metadata parsing, subtitles, audio/video controls, snapshots, and related playback features.
        - When VLC is installed on the build machine, the packaging script bundles VLC's lib, plugins, and share directories from /Applications/VLC.app.
        - VLC media player is released under GPLv2 or later.
        - libVLC, the embeddable VLC engine, is released under LGPLv2.1 or later.
        - Some bundled VLC plugins/modules/dependencies may carry additional or stronger license obligations depending on the VLC build.
        - Project: https://www.videolan.org/vlc/
        - Source: https://code.videolan.org/videolan/vlc
        - License files in VLC source: COPYING and COPYING.LIB

        mpv
        - Optional external fallback player when installed separately by the user.
        - Video Player does not bundle mpv.
        - mpv is GPLv2 or later by default, and can be built LGPLv2.1 or later with GPL features disabled.
        - Project: https://mpv.io/
        - Source: https://github.com/mpv-player/mpv

        Apple Frameworks
        - AppKit, AVKit, AVFoundation, Foundation, and related macOS SDK frameworks are used for the native app shell and Apple-native playback.
        - These are Apple platform frameworks, not bundled open source dependencies of this repository.

        No third-party Swift packages are currently included.

        This notice is informational and not legal advice. Review the upstream license files and the exact VLC/mpv builds you distribute.
        """
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"
    }
}
