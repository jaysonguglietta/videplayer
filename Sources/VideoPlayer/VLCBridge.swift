import AppKit
import Darwin
import Foundation

final class VLCBridge {
    private var api: DynamicLibVLC?
    private var instance: OpaquePointer?
    private var player: OpaquePointer?

    var isAvailable: Bool {
        DynamicLibVLC.findLibrary() != nil
    }

    var isPlaying: Bool {
        guard let api, let player else { return false }
        return api.isPlaying(player) == 1
    }

    var hasPlayer: Bool {
        player != nil
    }

    var currentTime: Double {
        guard let api, let player else { return 0 }
        return Double(api.getTime(player)) / 1000
    }

    var duration: Double {
        guard let api, let player else { return 0 }
        return Double(api.getLength(player)) / 1000
    }

    deinit {
        stop()
        if let instance {
            api?.releaseInstance(instance)
        }
    }

    func play(url: URL, in videoView: NSView, volume: Double, speed: Double) throws {
        let api = try loadAPI()
        let instance = try loadInstance(api: api)

        stopPlayer()

        let media: OpaquePointer?
        if url.isFileURL {
            media = url.path.withCString { path in
                api.mediaNewPath(instance, path)
            }
        } else {
            media = url.absoluteString.withCString { location in
                api.mediaNewLocation(instance, location)
            }
        }

        guard let media else {
            throw VLCBridgeError.playbackFailed("VLC could not open this media path.")
        }
        defer { api.mediaRelease(media) }

        guard let newPlayer = api.mediaPlayerNewFromMedia(media) else {
            throw VLCBridgeError.playbackFailed("VLC could not create a media player.")
        }

        player = newPlayer
        api.setNSObject(newPlayer, Unmanaged.passUnretained(videoView).toOpaque())
        _ = api.audioSetVolume(newPlayer, Int32(volume))
        _ = api.setRate(newPlayer, Float(speed))

        if api.play(newPlayer) != 0 {
            stopPlayer()
            throw VLCBridgeError.playbackFailed("VLC could not start playback.")
        }
    }

    func addSubtitle(url: URL) -> Bool {
        guard let api, let player else { return false }
        return url.absoluteString.withCString { uri in
            api.addSlave(player, 0, uri, true) == 0
        }
    }

    func audioTracks() -> [TrackOption] {
        guard let api, let player else { return [] }
        return trackOptions(from: api.audioTrackDescription(player), releaseWith: api.releaseTrackDescription)
    }

    func selectedAudioTrackID() -> Int32? {
        guard let api, let player else { return nil }
        return api.audioGetTrack(player)
    }

    func selectAudioTrack(id: Int32) -> Bool {
        guard let api, let player else { return false }
        return api.audioSetTrack(player, id) == 0
    }

    func subtitleTracks() -> [TrackOption] {
        guard let api, let player else { return [] }
        return trackOptions(from: api.subtitleTrackDescription(player), releaseWith: api.releaseTrackDescription)
    }

    func selectedSubtitleTrackID() -> Int32? {
        guard let api, let player else { return nil }
        return api.subtitleGetTrack(player)
    }

    func selectSubtitleTrack(id: Int32) -> Bool {
        guard let api, let player else { return false }
        return api.subtitleSetTrack(player, id) == 0
    }

    func subtitleDelaySeconds() -> Double {
        guard let api, let player else { return 0 }
        return Double(api.subtitleGetDelay(player)) / 1_000_000
    }

    func setSubtitleDelay(seconds: Double) -> Bool {
        guard let api, let player else { return false }
        return api.subtitleSetDelay(player, Int64(seconds * 1_000_000)) == 0
    }

    func togglePlayPause() {
        guard let api, let player else { return }
        api.pause(player)
    }

    func seek(seconds: Int) {
        setTime(max(currentTime + Double(seconds), 0))
    }

    func setTime(_ seconds: Double) {
        guard let api, let player else { return }
        api.setTime(player, Int64(max(seconds, 0) * 1000))
    }

    func setVolume(_ volume: Double) {
        guard let api, let player else { return }
        _ = api.audioSetVolume(player, Int32(volume))
    }

    func setSpeed(_ speed: Double) {
        guard let api, let player else { return }
        _ = api.setRate(player, Float(speed))
    }

    func stop() {
        stopPlayer()
    }

    private func loadAPI() throws -> DynamicLibVLC {
        if let api {
            return api
        }
        let loadedAPI = try DynamicLibVLC()
        api = loadedAPI
        return loadedAPI
    }

    private func loadInstance(api: DynamicLibVLC) throws -> OpaquePointer {
        if let instance {
            return instance
        }

        var arguments = [
            "--quiet",
            "--no-video-title-show",
            "--no-metadata-network-access"
        ]
        if let pluginPath = api.pluginPath {
            arguments.append("--plugin-path=\(pluginPath)")
        }

        let cStrings = arguments.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        let cArguments = cStrings.map { UnsafePointer<CChar>($0) }

        guard let createdInstance = cArguments.withUnsafeBufferPointer({ buffer in
            api.createInstance(Int32(arguments.count), buffer.baseAddress)
        }) else {
            throw VLCBridgeError.playbackFailed("VLC could not initialize its codec engine.")
        }

        instance = createdInstance
        return createdInstance
    }

    private func stopPlayer() {
        guard let api, let player else { return }
        api.stop(player)
        api.releasePlayer(player)
        self.player = nil
    }

    private func trackOptions(
        from head: UnsafeMutableRawPointer?,
        releaseWith release: (UnsafeMutableRawPointer?) -> Void
    ) -> [TrackOption] {
        guard let head else { return [] }
        defer { release(head) }

        var options: [TrackOption] = []
        var cursor: UnsafeMutablePointer<LibVLCTrackDescription>? = head.assumingMemoryBound(to: LibVLCTrackDescription.self)
        while let node = cursor {
            let description = node.pointee
            let name = description.psz_name.map { String(cString: $0) } ?? "Track \(description.i_id)"
            options.append(TrackOption(id: description.i_id, name: name))
            cursor = description.p_next
        }
        return options
    }
}

private struct LibVLCTrackDescription {
    var i_id: Int32
    var psz_name: UnsafeMutablePointer<CChar>?
    var p_next: UnsafeMutablePointer<LibVLCTrackDescription>?
}

private final class DynamicLibVLC {
    typealias CreateInstance = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer?
    typealias ReleaseInstance = @convention(c) (OpaquePointer?) -> Void
    typealias MediaNewPath = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias MediaNewLocation = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias MediaRelease = @convention(c) (OpaquePointer?) -> Void
    typealias MediaPlayerNewFromMedia = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias MediaPlayerRelease = @convention(c) (OpaquePointer?) -> Void
    typealias SetNSObject = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void
    typealias Play = @convention(c) (OpaquePointer?) -> Int32
    typealias Pause = @convention(c) (OpaquePointer?) -> Void
    typealias Stop = @convention(c) (OpaquePointer?) -> Void
    typealias IsPlaying = @convention(c) (OpaquePointer?) -> Int32
    typealias GetTime = @convention(c) (OpaquePointer?) -> Int64
    typealias GetLength = @convention(c) (OpaquePointer?) -> Int64
    typealias SetTime = @convention(c) (OpaquePointer?, Int64) -> Void
    typealias SetRate = @convention(c) (OpaquePointer?, Float) -> Int32
    typealias AudioSetVolume = @convention(c) (OpaquePointer?, Int32) -> Int32
    typealias AddSlave = @convention(c) (OpaquePointer?, Int32, UnsafePointer<CChar>?, Bool) -> Int32
    typealias TrackDescription = @convention(c) (OpaquePointer?) -> UnsafeMutableRawPointer?
    typealias ReleaseTrackDescription = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias GetTrack = @convention(c) (OpaquePointer?) -> Int32
    typealias SetTrack = @convention(c) (OpaquePointer?, Int32) -> Int32
    typealias GetDelay = @convention(c) (OpaquePointer?) -> Int64
    typealias SetDelay = @convention(c) (OpaquePointer?, Int64) -> Int32

    let pluginPath: String?
    let createInstance: CreateInstance
    let releaseInstance: ReleaseInstance
    let mediaNewPath: MediaNewPath
    let mediaNewLocation: MediaNewLocation
    let mediaRelease: MediaRelease
    let mediaPlayerNewFromMedia: MediaPlayerNewFromMedia
    let releasePlayer: MediaPlayerRelease
    let setNSObject: SetNSObject
    let play: Play
    let pause: Pause
    let stop: Stop
    let isPlaying: IsPlaying
    let getTime: GetTime
    let getLength: GetLength
    let setTime: SetTime
    let setRate: SetRate
    let audioSetVolume: AudioSetVolume
    let addSlave: AddSlave
    let audioTrackDescription: TrackDescription
    let audioGetTrack: GetTrack
    let audioSetTrack: SetTrack
    let subtitleTrackDescription: TrackDescription
    let subtitleGetTrack: GetTrack
    let subtitleSetTrack: SetTrack
    let subtitleGetDelay: GetDelay
    let subtitleSetDelay: SetDelay
    let releaseTrackDescription: ReleaseTrackDescription

    private let handle: UnsafeMutableRawPointer
    private let coreHandle: UnsafeMutableRawPointer?

    init() throws {
        guard let libraryURL = Self.findLibrary() else {
            throw VLCBridgeError.notInstalled
        }

        let coreHandle = Self.findCoreLibrary(for: libraryURL).flatMap {
            dlopen($0.path, RTLD_NOW | RTLD_GLOBAL)
        }

        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw VLCBridgeError.loadFailed(Self.lastDynamicLoaderError())
        }

        self.handle = handle
        self.coreHandle = coreHandle
        self.pluginPath = Self.pluginPath(for: libraryURL)
        self.createInstance = try Self.load("libvlc_new", from: handle, as: CreateInstance.self)
        self.releaseInstance = try Self.load("libvlc_release", from: handle, as: ReleaseInstance.self)
        self.mediaNewPath = try Self.load("libvlc_media_new_path", from: handle, as: MediaNewPath.self)
        self.mediaNewLocation = try Self.load("libvlc_media_new_location", from: handle, as: MediaNewLocation.self)
        self.mediaRelease = try Self.load("libvlc_media_release", from: handle, as: MediaRelease.self)
        self.mediaPlayerNewFromMedia = try Self.load("libvlc_media_player_new_from_media", from: handle, as: MediaPlayerNewFromMedia.self)
        self.releasePlayer = try Self.load("libvlc_media_player_release", from: handle, as: MediaPlayerRelease.self)
        self.setNSObject = try Self.load("libvlc_media_player_set_nsobject", from: handle, as: SetNSObject.self)
        self.play = try Self.load("libvlc_media_player_play", from: handle, as: Play.self)
        self.pause = try Self.load("libvlc_media_player_pause", from: handle, as: Pause.self)
        self.stop = try Self.load("libvlc_media_player_stop", from: handle, as: Stop.self)
        self.isPlaying = try Self.load("libvlc_media_player_is_playing", from: handle, as: IsPlaying.self)
        self.getTime = try Self.load("libvlc_media_player_get_time", from: handle, as: GetTime.self)
        self.getLength = try Self.load("libvlc_media_player_get_length", from: handle, as: GetLength.self)
        self.setTime = try Self.load("libvlc_media_player_set_time", from: handle, as: SetTime.self)
        self.setRate = try Self.load("libvlc_media_player_set_rate", from: handle, as: SetRate.self)
        self.audioSetVolume = try Self.load("libvlc_audio_set_volume", from: handle, as: AudioSetVolume.self)
        self.addSlave = try Self.load("libvlc_media_player_add_slave", from: handle, as: AddSlave.self)
        self.audioTrackDescription = try Self.load("libvlc_audio_get_track_description", from: handle, as: TrackDescription.self)
        self.audioGetTrack = try Self.load("libvlc_audio_get_track", from: handle, as: GetTrack.self)
        self.audioSetTrack = try Self.load("libvlc_audio_set_track", from: handle, as: SetTrack.self)
        self.subtitleTrackDescription = try Self.load("libvlc_video_get_spu_description", from: handle, as: TrackDescription.self)
        self.subtitleGetTrack = try Self.load("libvlc_video_get_spu", from: handle, as: GetTrack.self)
        self.subtitleSetTrack = try Self.load("libvlc_video_set_spu", from: handle, as: SetTrack.self)
        self.subtitleGetDelay = try Self.load("libvlc_video_get_spu_delay", from: handle, as: GetDelay.self)
        self.subtitleSetDelay = try Self.load("libvlc_video_set_spu_delay", from: handle, as: SetDelay.self)
        self.releaseTrackDescription = try Self.load("libvlc_track_description_list_release", from: handle, as: ReleaseTrackDescription.self)
    }

    deinit {
        dlclose(handle)
        if let coreHandle {
            dlclose(coreHandle)
        }
    }

    static func findLibrary() -> URL? {
        let bundledLibrary = Bundle.main.resourceURL?
            .appendingPathComponent("VLC/lib/libvlc.dylib")
            .path
        let candidates = [
            bundledLibrary,
            "/Applications/VLC.app/Contents/MacOS/lib/libvlc.dylib",
            "/opt/homebrew/lib/libvlc.dylib",
            "/usr/local/lib/libvlc.dylib"
        ].compactMap(\.self)
        let fileManager = FileManager.default
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private static func findCoreLibrary(for libraryURL: URL) -> URL? {
        let candidate = libraryURL
            .deletingLastPathComponent()
            .appendingPathComponent("libvlccore.dylib")
        return FileManager.default.isReadableFile(atPath: candidate.path) ? candidate : nil
    }

    private static func pluginPath(for libraryURL: URL) -> String? {
        let macOSDirectory = libraryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidate = macOSDirectory.appendingPathComponent("plugins").path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
        guard let rawSymbol = dlsym(handle, symbol) else {
            throw VLCBridgeError.loadFailed("Missing VLC symbol: \(symbol)")
        }
        return unsafeBitCast(rawSymbol, to: type)
    }

    private static func lastDynamicLoaderError() -> String {
        guard let error = dlerror() else { return "Unknown dynamic loader error." }
        return String(cString: error)
    }
}

enum VLCBridgeError: LocalizedError {
    case notInstalled
    case loadFailed(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "VLC is not installed. Install VLC or mpv to enable broad MKV, WebM, AVI, FLV, and codec playback."
        case .loadFailed(let detail):
            "VLC could not be loaded: \(detail)"
        case .playbackFailed(let detail):
            detail
        }
    }
}
