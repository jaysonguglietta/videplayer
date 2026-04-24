import AppKit
import Darwin
import Foundation

final class VLCBridge {
    private var api: DynamicLibVLC?
    private var instance: OpaquePointer?
    private var player: OpaquePointer?
    private var equalizer: OpaquePointer?
    private var eventManager: OpaquePointer?
    private var eventSink: VLCEventSink?
    private var attachedEventTypes: [Int32] = []

    var eventHandler: ((VLCPlaybackEvent) -> Void)?

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
        if let equalizer {
            api?.equalizerRelease?(equalizer)
        }
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
        attachEvents(to: newPlayer, api: api)
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

    func audioDelaySeconds() -> Double {
        guard let api, let player, let audioGetDelay = api.audioGetDelay else { return 0 }
        return Double(audioGetDelay(player)) / 1_000_000
    }

    func setAudioDelay(seconds: Double) -> Bool {
        guard let api, let player, let audioSetDelay = api.audioSetDelay else { return false }
        return audioSetDelay(player, Int64(seconds * 1_000_000)) == 0
    }

    func audioOutputDevices() -> [AudioOutputDevice] {
        guard let api, let player, let deviceEnum = api.audioOutputDeviceEnum else { return [] }
        guard let head = deviceEnum(player) else { return [] }
        defer { api.audioOutputDeviceListRelease?(head) }

        var devices: [AudioOutputDevice] = []
        var cursor: UnsafeMutablePointer<LibVLCAudioOutputDevice>? = head.assumingMemoryBound(to: LibVLCAudioOutputDevice.self)
        while let node = cursor {
            let device = node.pointee
            if let idPointer = device.psz_device {
                let id = String(cString: idPointer)
                let name = device.psz_description.map { String(cString: $0) } ?? id
                devices.append(AudioOutputDevice(id: id, name: name))
            }
            cursor = device.p_next
        }
        return devices
    }

    func selectAudioOutputDevice(id: String) -> Bool {
        guard let api, let player, let deviceSet = api.audioOutputDeviceSet else { return false }
        id.withCString { deviceID in
            deviceSet(player, nil, deviceID)
        }
        return true
    }

    func chapters() -> [ChapterOption] {
        guard let api, let player, let getChapters = api.getChapterDescriptions else { return [] }

        var rawChapters: UnsafeMutableRawPointer?
        let count = getChapters(player, -1, &rawChapters)
        guard count > 0, let rawChapters else { return [] }
        defer { api.releaseChapterDescriptions?(rawChapters, UInt32(count)) }

        let chapters = rawChapters.assumingMemoryBound(to: UnsafeMutablePointer<LibVLCChapterDescription>?.self)
        return (0..<Int(count)).compactMap { index in
            guard let chapter = chapters[index] else { return nil }
            let description = chapter.pointee
            let fallbackName = "Chapter \(index + 1)"
            let name = description.psz_name.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            return ChapterOption(
                index: Int32(index),
                name: name,
                startTime: Double(description.i_time_offset) / 1000,
                duration: Double(description.i_duration) / 1000
            )
        }
    }

    func selectedChapterIndex() -> Int32? {
        guard let api, let player, let getChapter = api.getChapter else { return nil }
        let value = getChapter(player)
        return value >= 0 ? value : nil
    }

    func selectChapter(index: Int32) -> Bool {
        guard let api, let player, let setChapter = api.setChapter else { return false }
        setChapter(player, index)
        return true
    }

    func previousChapter() {
        guard let api, let player, let previousChapter = api.previousChapter else { return }
        previousChapter(player)
    }

    func nextChapter() {
        guard let api, let player, let nextChapter = api.nextChapter else { return }
        nextChapter(player)
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

    func takeSnapshot(to url: URL) -> Bool {
        guard let api, let player, let takeSnapshot = api.takeSnapshot else { return false }
        return url.path.withCString { path in
            takeSnapshot(player, 0, path, 0, 0) == 0
        }
    }

    func applyAudioPreset(_ preset: AudioPreset) -> Bool {
        guard let api, let player, let setEqualizer = api.setEqualizer else { return false }

        if let equalizer {
            api.equalizerRelease?(equalizer)
            self.equalizer = nil
        }

        guard preset != .flat else {
            return setEqualizer(player, nil) == 0
        }

        guard
            let equalizerNew = api.equalizerNew,
            let equalizerSetPreamp = api.equalizerSetPreamp,
            let equalizerSetAmp = api.equalizerSetAmp,
            let newEqualizer = equalizerNew()
        else {
            return false
        }
        equalizer = newEqualizer

        _ = equalizerSetPreamp(newEqualizer, preset.preamp)
        for (index, value) in preset.bandAdjustments.enumerated() {
            _ = equalizerSetAmp(newEqualizer, value, UInt32(index))
        }
        return setEqualizer(player, newEqualizer) == 0
    }

    func applyVideoAdjustments(_ adjustments: VideoAdjustments) -> Bool {
        guard
            let api,
            let player,
            let setAdjustInt = api.videoSetAdjustInt,
            let setAdjustFloat = api.videoSetAdjustFloat
        else {
            return false
        }

        setAdjustInt(player, VLCVideoAdjustOption.enable, adjustments.isDefault ? 0 : 1)
        guard !adjustments.isDefault else { return true }

        setAdjustFloat(player, VLCVideoAdjustOption.brightness, Float(adjustments.brightness))
        setAdjustFloat(player, VLCVideoAdjustOption.contrast, Float(adjustments.contrast))
        setAdjustFloat(player, VLCVideoAdjustOption.saturation, Float(adjustments.saturation))
        setAdjustFloat(player, VLCVideoAdjustOption.hue, Float(adjustments.hue))
        setAdjustFloat(player, VLCVideoAdjustOption.gamma, Float(adjustments.gamma))
        return true
    }

    static func inspectMedia(url: URL) -> VLCMediaInspection? {
        do {
            let api = try DynamicLibVLC()
            if let pluginPath = api.pluginPath {
                setenv("VLC_PLUGIN_PATH", pluginPath, 1)
            }
            if let dataPath = api.dataPath {
                setenv("VLC_DATA_PATH", dataPath, 1)
            }

            let arguments = [
                "--quiet",
                "--no-video-title-show",
                "--no-metadata-network-access"
            ]
            let cStrings = arguments.map { strdup($0) }
            defer { cStrings.forEach { free($0) } }
            let cArguments = cStrings.map { UnsafePointer<CChar>($0) }
            guard let instance = cArguments.withUnsafeBufferPointer({ buffer in
                api.createInstance(Int32(arguments.count), buffer.baseAddress)
            }) else {
                return nil
            }
            defer { api.releaseInstance(instance) }

            let media: OpaquePointer?
            if url.isFileURL {
                media = url.path.withCString { api.mediaNewPath(instance, $0) }
            } else {
                media = url.absoluteString.withCString { api.mediaNewLocation(instance, $0) }
            }

            guard let media else { return nil }
            defer { api.mediaRelease(media) }

            let parseFlags: Int32 = url.isFileURL ? 0x02 : 0x01
            if let parse = api.mediaParseWithOptions {
                _ = parse(media, parseFlags, 1500)
                waitForMediaParse(api: api, media: media)
            }

            let metadata = inspectedMetadata(api: api, media: media)
            let trackSummary = inspectedTrackSummary(api: api, media: media)
            let duration = api.mediaGetDuration.map { Double($0(media)) / 1000 }.flatMap { $0 > 0 ? $0 : nil }
            let preferredTitle = metadata.first(where: { $0.0 == "Title" })?.1
                ?? metadata.first(where: { $0.0 == "Show" })?.1

            guard preferredTitle != nil || !metadata.isEmpty || !trackSummary.isEmpty || duration != nil else {
                return nil
            }

            return VLCMediaInspection(
                preferredTitle: preferredTitle,
                duration: duration,
                metadata: metadata,
                trackSummary: trackSummary
            )
        } catch {
            return nil
        }
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

        if let pluginPath = api.pluginPath {
            setenv("VLC_PLUGIN_PATH", pluginPath, 1)
        }
        if let dataPath = api.dataPath {
            setenv("VLC_DATA_PATH", dataPath, 1)
        }

        let arguments = [
            "--quiet",
            "--no-video-title-show",
            "--no-metadata-network-access"
        ]

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
        detachEvents(api: api)
        api.stop(player)
        api.releasePlayer(player)
        self.player = nil
    }

    private func attachEvents(to player: OpaquePointer, api: DynamicLibVLC) {
        guard let eventManager = api.mediaPlayerEventManager?(player) else { return }
        let sink = VLCEventSink { [weak self] event in
            self?.eventHandler?(event)
        }
        let sinkPointer = Unmanaged.passUnretained(sink).toOpaque()
        let eventTypes = VLCPlaybackEvent.libvlcEventTypes

        for eventType in eventTypes {
            _ = api.eventAttach?(eventManager, eventType, vlcEventCallback, sinkPointer)
        }

        self.eventManager = eventManager
        eventSink = sink
        attachedEventTypes = eventTypes
    }

    private func detachEvents(api: DynamicLibVLC) {
        guard let eventManager, let eventSink else { return }
        let sinkPointer = Unmanaged.passUnretained(eventSink).toOpaque()
        for eventType in attachedEventTypes {
            api.eventDetach?(eventManager, eventType, vlcEventCallback, sinkPointer)
        }
        self.eventManager = nil
        self.eventSink = nil
        attachedEventTypes = []
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

    private static func waitForMediaParse(api: DynamicLibVLC, media: OpaquePointer) {
        guard let parsedStatus = api.mediaGetParsedStatus else { return }

        let deadline = Date().addingTimeInterval(1.8)
        while Date() < deadline {
            let status = parsedStatus(media)
            if status != 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private static func inspectedMetadata(
        api: DynamicLibVLC,
        media: OpaquePointer
    ) -> [(String, String)] {
        guard let getMeta = api.mediaGetMeta else { return [] }

        let keys: [(String, Int32)] = [
            ("Title", 0),
            ("Artist", 1),
            ("Album", 4),
            ("Track", 5),
            ("Date", 8),
            ("Language", 11),
            ("Publisher", 13),
            ("Encoded By", 14),
            ("Artwork", 15),
            ("Director", 18),
            ("Season", 19),
            ("Episode", 20),
            ("Show", 21),
            ("Actors", 22)
        ]

        var metadata: [(String, String)] = []
        for entry in keys {
            guard let valuePointer = getMeta(media, entry.1) else { continue }
            defer { api.free?(valuePointer) }
            let value = String(cString: valuePointer.assumingMemoryBound(to: CChar.self))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            metadata.append((entry.0, value))
        }
        return metadata
    }

    private static func inspectedTrackSummary(
        api: DynamicLibVLC,
        media: OpaquePointer
    ) -> [String] {
        guard let tracksGet = api.mediaTracksGet else { return [] }

        var rawTracks: UnsafeMutableRawPointer?
        let count = tracksGet(media, &rawTracks)
        guard count > 0, let rawTracks else { return [] }
        defer { api.mediaTracksRelease?(rawTracks, count) }

        var audioTracks: [String] = []
        var videoTracks: [String] = []
        var subtitleTracks: [String] = []
        let tracks = rawTracks.assumingMemoryBound(to: UnsafeMutablePointer<LibVLCMediaTrack>?.self)

        for index in 0..<Int(count) {
            guard let trackPointer = tracks[index] else { continue }
            let track = trackPointer.pointee
            let codec = api.mediaCodecDescription?(track.i_type, track.i_codec).map(String.init(cString:))
                ?? fourCC(track.i_codec)
            let language = track.psz_language.map { String(cString: $0) }
                .flatMap { $0.isEmpty || $0 == "und" ? nil : $0 }
            let description = track.psz_description.map { String(cString: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let suffix = [language, description].compactMap(\.self).joined(separator: ", ")
            let summary = suffix.isEmpty ? codec : "\(codec) (\(suffix))"

            switch track.i_type {
            case 0:
                audioTracks.append(summary)
            case 1:
                videoTracks.append(summary)
            case 2:
                subtitleTracks.append(summary)
            default:
                break
            }
        }

        var lines: [String] = []
        if !videoTracks.isEmpty {
            lines.append("Video Tracks: \(videoTracks.joined(separator: "; "))")
        }
        if !audioTracks.isEmpty {
            lines.append("Audio Tracks: \(audioTracks.joined(separator: "; "))")
        }
        if !subtitleTracks.isEmpty {
            lines.append("Subtitle Tracks: \(subtitleTracks.joined(separator: "; "))")
        }
        return lines
    }

    private static func fourCC(_ value: UInt32) -> String {
        let scalars = [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
        let string = String(bytes: scalars, encoding: .ascii) ?? "Unknown"
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : string
    }
}

private struct LibVLCTrackDescription {
    var i_id: Int32
    var psz_name: UnsafeMutablePointer<CChar>?
    var p_next: UnsafeMutablePointer<LibVLCTrackDescription>?
}

private struct LibVLCAudioOutputDevice {
    var p_next: UnsafeMutablePointer<LibVLCAudioOutputDevice>?
    var psz_device: UnsafeMutablePointer<CChar>?
    var psz_description: UnsafeMutablePointer<CChar>?
}

private struct LibVLCChapterDescription {
    var i_time_offset: Int64
    var i_duration: Int64
    var psz_name: UnsafeMutablePointer<CChar>?
}

private struct LibVLCMediaTrack {
    var i_codec: UInt32
    var i_original_fourcc: UInt32
    var i_id: Int32
    var i_type: Int32
    var i_profile: Int32
    var i_level: Int32
    var trackData: UnsafeMutableRawPointer?
    var i_bitrate: UInt32
    var psz_language: UnsafeMutablePointer<CChar>?
    var psz_description: UnsafeMutablePointer<CChar>?
}

private enum VLCVideoAdjustOption {
    static let enable: UInt32 = 0
    static let contrast: UInt32 = 1
    static let brightness: UInt32 = 2
    static let hue: UInt32 = 3
    static let saturation: UInt32 = 4
    static let gamma: UInt32 = 5
}

private struct LibVLCEvent {
    var type: Int32
    var p_obj: UnsafeMutableRawPointer?
}

enum VLCPlaybackEvent {
    case opening
    case buffering
    case playing
    case paused
    case stopped
    case ended
    case error
    case lengthChanged
    case chapterChanged
    case tracksChanged

    fileprivate static let libvlcEventTypes: [Int32] = [
        0x102,
        0x103,
        0x104,
        0x105,
        0x106,
        0x109,
        0x10a,
        0x111,
        0x114,
        0x115,
        0x116,
        0x11c,
        0x11d
    ]

    fileprivate init?(libvlcEventType: Int32) {
        switch libvlcEventType {
        case 0x102:
            self = .opening
        case 0x103:
            self = .buffering
        case 0x104:
            self = .playing
        case 0x105:
            self = .paused
        case 0x106:
            self = .stopped
        case 0x109:
            self = .ended
        case 0x10a:
            self = .error
        case 0x111:
            self = .lengthChanged
        case 0x114, 0x115, 0x116:
            self = .tracksChanged
        case 0x11c:
            self = .tracksChanged
        case 0x11d:
            self = .chapterChanged
        default:
            return nil
        }
    }
}

private final class VLCEventSink {
    private let handler: (VLCPlaybackEvent) -> Void

    init(handler: @escaping (VLCPlaybackEvent) -> Void) {
        self.handler = handler
    }

    func handle(eventType: Int32) {
        guard let event = VLCPlaybackEvent(libvlcEventType: eventType) else { return }
        handler(event)
    }
}

private let vlcEventCallback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void = { eventPointer, userData in
    guard let eventPointer, let userData else { return }
    let event = eventPointer.assumingMemoryBound(to: LibVLCEvent.self).pointee
    let sink = Unmanaged<VLCEventSink>.fromOpaque(userData).takeUnretainedValue()
    sink.handle(eventType: event.type)
}

private final class DynamicLibVLC {
    typealias CreateInstance = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer?
    typealias ReleaseInstance = @convention(c) (OpaquePointer?) -> Void
    typealias MediaNewPath = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias MediaNewLocation = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias MediaRelease = @convention(c) (OpaquePointer?) -> Void
    typealias MediaParseWithOptions = @convention(c) (OpaquePointer?, Int32, Int32) -> Int32
    typealias MediaGetParsedStatus = @convention(c) (OpaquePointer?) -> Int32
    typealias MediaGetMeta = @convention(c) (OpaquePointer?, Int32) -> UnsafeMutableRawPointer?
    typealias MediaGetDuration = @convention(c) (OpaquePointer?) -> Int64
    typealias MediaTracksGet = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt32
    typealias MediaTracksRelease = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void
    typealias MediaCodecDescription = @convention(c) (Int32, UInt32) -> UnsafePointer<CChar>?
    typealias MediaPlayerNewFromMedia = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias MediaPlayerRelease = @convention(c) (OpaquePointer?) -> Void
    typealias EventCallback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias MediaPlayerEventManager = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias EventAttach = @convention(c) (OpaquePointer?, Int32, EventCallback?, UnsafeMutableRawPointer?) -> Int32
    typealias EventDetach = @convention(c) (OpaquePointer?, Int32, EventCallback?, UnsafeMutableRawPointer?) -> Void
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
    typealias AudioOutputDeviceEnum = @convention(c) (OpaquePointer?) -> UnsafeMutableRawPointer?
    typealias AudioOutputDeviceListRelease = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias AudioOutputDeviceSet = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    typealias ChapterDescriptions = @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    typealias ReleaseChapterDescriptions = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void
    typealias GetChapter = @convention(c) (OpaquePointer?) -> Int32
    typealias SetChapter = @convention(c) (OpaquePointer?, Int32) -> Void
    typealias ChapterControl = @convention(c) (OpaquePointer?) -> Void
    typealias TakeSnapshot = @convention(c) (OpaquePointer?, UInt32, UnsafePointer<CChar>?, UInt32, UInt32) -> Int32
    typealias VideoSetAdjustInt = @convention(c) (OpaquePointer?, UInt32, Int32) -> Void
    typealias VideoSetAdjustFloat = @convention(c) (OpaquePointer?, UInt32, Float) -> Void
    typealias EqualizerNew = @convention(c) () -> OpaquePointer?
    typealias EqualizerRelease = @convention(c) (OpaquePointer?) -> Void
    typealias EqualizerSetPreamp = @convention(c) (OpaquePointer?, Float) -> Int32
    typealias EqualizerSetAmp = @convention(c) (OpaquePointer?, Float, UInt32) -> Int32
    typealias SetEqualizer = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    typealias LibVLCFree = @convention(c) (UnsafeMutableRawPointer?) -> Void

    let pluginPath: String?
    let dataPath: String?
    let createInstance: CreateInstance
    let releaseInstance: ReleaseInstance
    let mediaNewPath: MediaNewPath
    let mediaNewLocation: MediaNewLocation
    let mediaRelease: MediaRelease
    let mediaParseWithOptions: MediaParseWithOptions?
    let mediaGetParsedStatus: MediaGetParsedStatus?
    let mediaGetMeta: MediaGetMeta?
    let mediaGetDuration: MediaGetDuration?
    let mediaTracksGet: MediaTracksGet?
    let mediaTracksRelease: MediaTracksRelease?
    let mediaCodecDescription: MediaCodecDescription?
    let mediaPlayerNewFromMedia: MediaPlayerNewFromMedia
    let releasePlayer: MediaPlayerRelease
    let mediaPlayerEventManager: MediaPlayerEventManager?
    let eventAttach: EventAttach?
    let eventDetach: EventDetach?
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
    let audioGetDelay: GetDelay?
    let audioSetDelay: SetDelay?
    let audioOutputDeviceEnum: AudioOutputDeviceEnum?
    let audioOutputDeviceListRelease: AudioOutputDeviceListRelease?
    let audioOutputDeviceSet: AudioOutputDeviceSet?
    let getChapterDescriptions: ChapterDescriptions?
    let releaseChapterDescriptions: ReleaseChapterDescriptions?
    let getChapter: GetChapter?
    let setChapter: SetChapter?
    let previousChapter: ChapterControl?
    let nextChapter: ChapterControl?
    let takeSnapshot: TakeSnapshot?
    let videoSetAdjustInt: VideoSetAdjustInt?
    let videoSetAdjustFloat: VideoSetAdjustFloat?
    let equalizerNew: EqualizerNew?
    let equalizerRelease: EqualizerRelease?
    let equalizerSetPreamp: EqualizerSetPreamp?
    let equalizerSetAmp: EqualizerSetAmp?
    let setEqualizer: SetEqualizer?
    let free: LibVLCFree?

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
        self.dataPath = Self.dataPath(for: libraryURL)
        self.createInstance = try Self.load("libvlc_new", from: handle, as: CreateInstance.self)
        self.releaseInstance = try Self.load("libvlc_release", from: handle, as: ReleaseInstance.self)
        self.mediaNewPath = try Self.load("libvlc_media_new_path", from: handle, as: MediaNewPath.self)
        self.mediaNewLocation = try Self.load("libvlc_media_new_location", from: handle, as: MediaNewLocation.self)
        self.mediaRelease = try Self.load("libvlc_media_release", from: handle, as: MediaRelease.self)
        self.mediaParseWithOptions = Self.loadOptional("libvlc_media_parse_with_options", from: handle, as: MediaParseWithOptions.self)
        self.mediaGetParsedStatus = Self.loadOptional("libvlc_media_get_parsed_status", from: handle, as: MediaGetParsedStatus.self)
        self.mediaGetMeta = Self.loadOptional("libvlc_media_get_meta", from: handle, as: MediaGetMeta.self)
        self.mediaGetDuration = Self.loadOptional("libvlc_media_get_duration", from: handle, as: MediaGetDuration.self)
        self.mediaTracksGet = Self.loadOptional("libvlc_media_tracks_get", from: handle, as: MediaTracksGet.self)
        self.mediaTracksRelease = Self.loadOptional("libvlc_media_tracks_release", from: handle, as: MediaTracksRelease.self)
        self.mediaCodecDescription = Self.loadOptional("libvlc_media_get_codec_description", from: handle, as: MediaCodecDescription.self)
        self.mediaPlayerNewFromMedia = try Self.load("libvlc_media_player_new_from_media", from: handle, as: MediaPlayerNewFromMedia.self)
        self.releasePlayer = try Self.load("libvlc_media_player_release", from: handle, as: MediaPlayerRelease.self)
        self.mediaPlayerEventManager = Self.loadOptional("libvlc_media_player_event_manager", from: handle, as: MediaPlayerEventManager.self)
        self.eventAttach = Self.loadOptional("libvlc_event_attach", from: handle, as: EventAttach.self)
        self.eventDetach = Self.loadOptional("libvlc_event_detach", from: handle, as: EventDetach.self)
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
        self.audioGetDelay = Self.loadOptional("libvlc_audio_get_delay", from: handle, as: GetDelay.self)
        self.audioSetDelay = Self.loadOptional("libvlc_audio_set_delay", from: handle, as: SetDelay.self)
        self.audioOutputDeviceEnum = Self.loadOptional("libvlc_audio_output_device_enum", from: handle, as: AudioOutputDeviceEnum.self)
        self.audioOutputDeviceListRelease = Self.loadOptional("libvlc_audio_output_device_list_release", from: handle, as: AudioOutputDeviceListRelease.self)
        self.audioOutputDeviceSet = Self.loadOptional("libvlc_audio_output_device_set", from: handle, as: AudioOutputDeviceSet.self)
        self.getChapterDescriptions = Self.loadOptional("libvlc_media_player_get_full_chapter_descriptions", from: handle, as: ChapterDescriptions.self)
        self.releaseChapterDescriptions = Self.loadOptional("libvlc_chapter_descriptions_release", from: handle, as: ReleaseChapterDescriptions.self)
        self.getChapter = Self.loadOptional("libvlc_media_player_get_chapter", from: handle, as: GetChapter.self)
        self.setChapter = Self.loadOptional("libvlc_media_player_set_chapter", from: handle, as: SetChapter.self)
        self.previousChapter = Self.loadOptional("libvlc_media_player_previous_chapter", from: handle, as: ChapterControl.self)
        self.nextChapter = Self.loadOptional("libvlc_media_player_next_chapter", from: handle, as: ChapterControl.self)
        self.takeSnapshot = Self.loadOptional("libvlc_video_take_snapshot", from: handle, as: TakeSnapshot.self)
        self.videoSetAdjustInt = Self.loadOptional("libvlc_video_set_adjust_int", from: handle, as: VideoSetAdjustInt.self)
        self.videoSetAdjustFloat = Self.loadOptional("libvlc_video_set_adjust_float", from: handle, as: VideoSetAdjustFloat.self)
        self.equalizerNew = Self.loadOptional("libvlc_audio_equalizer_new", from: handle, as: EqualizerNew.self)
        self.equalizerRelease = Self.loadOptional("libvlc_audio_equalizer_release", from: handle, as: EqualizerRelease.self)
        self.equalizerSetPreamp = Self.loadOptional("libvlc_audio_equalizer_set_preamp", from: handle, as: EqualizerSetPreamp.self)
        self.equalizerSetAmp = Self.loadOptional("libvlc_audio_equalizer_set_amp_at_index", from: handle, as: EqualizerSetAmp.self)
        self.setEqualizer = Self.loadOptional("libvlc_media_player_set_equalizer", from: handle, as: SetEqualizer.self)
        self.free = Self.loadOptional("libvlc_free", from: handle, as: LibVLCFree.self)
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
        let runtimeRoot = libraryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            runtimeRoot.appendingPathComponent("plugins").path,
            runtimeRoot.appendingPathComponent("lib/vlc/plugins").path
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func dataPath(for libraryURL: URL) -> String? {
        let runtimeRoot = libraryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            runtimeRoot.appendingPathComponent("share").path,
            runtimeRoot.appendingPathComponent("share/vlc").path
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
        guard let rawSymbol = dlsym(handle, symbol) else {
            throw VLCBridgeError.loadFailed("Missing VLC symbol: \(symbol)")
        }
        return unsafeBitCast(rawSymbol, to: type)
    }

    private static func loadOptional<T>(_ symbol: String, from handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let rawSymbol = dlsym(handle, symbol) else { return nil }
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
