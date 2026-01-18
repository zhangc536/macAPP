import Foundation

struct Version: Codable {
    var version: String
    var url: String
    var sha256: String?
    var size: Int64?
    var releaseNotes: String?
    var releasedAt: Date?
}
