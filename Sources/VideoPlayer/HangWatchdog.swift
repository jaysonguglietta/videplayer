import Foundation

enum HangWatchdog {
    private static let queue = DispatchQueue(label: "com.jaysonguglietta.videoplayer.hang-watchdog", qos: .utility)
    private static var timer: DispatchSourceTimer?
    private static var lastMainThreadBeat = Date()
    private static var lastWarning = Date(timeIntervalSince1970: 0)

    static func start(threshold: TimeInterval = 5) {
        guard timer == nil else { return }
        lastMainThreadBeat = Date()
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + 1, repeating: 1)
        newTimer.setEventHandler {
            DispatchQueue.main.async {
                lastMainThreadBeat = Date()
            }

            let now = Date()
            let lag = now.timeIntervalSince(lastMainThreadBeat)
            guard lag > threshold, now.timeIntervalSince(lastWarning) > threshold else { return }
            lastWarning = now
            AppLogger.warning(String(format: "Main thread watchdog observed %.1fs without a heartbeat", lag), flush: true)
        }
        timer = newTimer
        newTimer.resume()
        AppLogger.info("Hang watchdog started threshold=\(threshold)s", flush: true)
    }
}
