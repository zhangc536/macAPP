import Foundation

struct Project: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var path: String?
    var ports: [Int]?
    var scripts: [String: String]?
    var scriptUrls: [String: String]?
    var launcherPath: String?
    var pid: Int?
    var status: String = "stopped"
    var logPath: String = "app.log"
    var needsSudo: [String: Bool]?
}
