import Foundation

struct VLCMediaInspection {
    let preferredTitle: String?
    let duration: Double?
    let metadata: [(String, String)]
    let trackSummary: [String]

    var detailLines: [String] {
        metadata.map { "\($0): \($1)" } + trackSummary
    }
}
