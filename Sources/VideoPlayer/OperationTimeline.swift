import Foundation

struct OperationTimelineEvent: Codable, Equatable {
    let id: UUID
    let name: String
    let detail: String
    let startedAt: Date
    let endedAt: Date?

    var duration: TimeInterval? {
        endedAt?.timeIntervalSince(startedAt)
    }
}

enum OperationTimeline {
    private static let queue = DispatchQueue(label: "com.jaysonguglietta.videoplayer.operation-timeline")
    private static var events: [OperationTimelineEvent] = []
    private static let maximumEvents = 200

    @discardableResult
    static func begin(_ name: String, detail: String = "") -> UUID {
        let event = OperationTimelineEvent(
            id: UUID(),
            name: name,
            detail: detail,
            startedAt: Date(),
            endedAt: nil
        )
        queue.sync {
            events.append(event)
            trimIfNeeded()
        }
        AppLogger.debug("Operation started id=\(event.id.uuidString) name=\(name) detail=\(detail)")
        return event.id
    }

    static func end(_ id: UUID, detail: String? = nil) {
        let completed: OperationTimelineEvent? = queue.sync {
            guard let index = events.lastIndex(where: { $0.id == id }) else { return nil }
            let prior = events[index]
            let event = OperationTimelineEvent(
                id: prior.id,
                name: prior.name,
                detail: detail ?? prior.detail,
                startedAt: prior.startedAt,
                endedAt: Date()
            )
            events[index] = event
            return event
        }
        if let completed, let duration = completed.duration {
            AppLogger.info(String(
                format: "Operation completed id=%@ name=%@ duration=%.3fs detail=%@",
                completed.id.uuidString,
                completed.name,
                duration,
                completed.detail
            ))
        }
    }

    static func record(_ name: String, detail: String = "") {
        let id = begin(name, detail: detail)
        end(id)
    }

    static func snapshot() -> [OperationTimelineEvent] {
        queue.sync { events }
    }

    static func reportText(now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = snapshot().map { event -> String in
            let status: String
            if let duration = event.duration {
                status = String(format: "completed %.3fs", duration)
            } else {
                status = String(format: "running %.3fs", now.timeIntervalSince(event.startedAt))
            }
            let detail = event.detail.isEmpty ? "" : " | \(event.detail)"
            return "\(formatter.string(from: event.startedAt)) | \(event.name) | \(status)\(detail)"
        }
        return (["Video Player Operation Timeline", "==============================="] + lines).joined(separator: "\n")
    }

    private static func trimIfNeeded() {
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
    }
}
