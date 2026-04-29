import Foundation

final class MPVBridge {
    private var process: Process?
    private var inputPipe: Pipe?

    var executablePath: String? {
        Self.findExecutable()
    }

    var isAvailable: Bool {
        executablePath != nil
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func play(url: URL, volume: Double, speed: Double, onExit: @escaping () -> Void) throws {
        stop()

        guard let executablePath else {
            throw MPVBridgeError.notInstalled
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "--force-window=yes",
            "--keep-open=yes",
            "--input-terminal=no",
            "--input-file=/dev/stdin",
            "--quiet",
            "--volume=\(Int(volume))",
            "--speed=\(speed)",
            url.isFileURL ? url.path : url.absoluteString
        ]
        process.standardInput = pipe
        process.terminationHandler = { _ in
            DispatchQueue.main.async(execute: onExit)
        }

        try process.run()
        self.process = process
        self.inputPipe = pipe
    }

    func togglePlayPause() {
        send("cycle pause")
    }

    func seek(seconds: Int) {
        send("seek \(seconds) relative")
    }

    func setTime(_ seconds: Double) {
        send("seek \(seconds) absolute")
    }

    func setVolume(_ volume: Double) {
        send("set volume \(Int(volume))")
    }

    func setSpeed(_ speed: Double) {
        send("set speed \(speed)")
    }

    func stop() {
        if process?.isRunning == true {
            send("quit")
            process?.terminate()
        }
        process = nil
        inputPipe = nil
    }

    private func send(_ command: String) {
        guard let data = "\(command)\n".data(using: .utf8) else { return }
        do {
            try inputPipe?.fileHandleForWriting.write(contentsOf: data)
        } catch {
            // mpv may already have exited; the UI will update from the termination handler.
        }
    }

    static func candidateExecutablePaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var candidates = [
            "/opt/homebrew/bin/mpv",
            "/usr/local/bin/mpv",
            "/Applications/mpv.app/Contents/MacOS/mpv"
        ]

        if environment["VIDEOPLAYER_ALLOW_PATH_MPV"] == "1" {
            let pathEntries = (environment["PATH"] ?? "")
                .split(separator: ":")
                .map(String.init)
            candidates.append(contentsOf: pathEntries.map { "\($0)/mpv" })
        }

        return candidates
    }

    private static func findExecutable() -> String? {
        let fileManager = FileManager.default
        return candidateExecutablePaths().first { fileManager.isExecutableFile(atPath: $0) }
    }
}

enum MPVBridgeError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "mpv is not installed. Install it with Homebrew to enable VLC-like MKV, WebM, AVI, FLV, and broad codec playback."
        }
    }
}
