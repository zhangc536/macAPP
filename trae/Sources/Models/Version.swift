import Foundation

struct Version: Codable {
    var version: String
    var url: String
    var releaseNotes: String?
    var releasedAt: Date?
}
