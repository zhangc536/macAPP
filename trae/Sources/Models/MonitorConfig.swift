import Foundation

enum MonitorType: String, CaseIterable, Codable {
    case log = "log"
    case port = "port"
    case process = "process"
    case comprehensive = "comprehensive"
    case directory = "directory"
    case network = "network"
}

struct MonitorConfig: Codable {
    var projectId: String
    var type: MonitorType
    var target: String // 日志路径、端口号、进程ID等
    var refreshInterval: Int = 1 // 刷新间隔（秒）
    var command: String? // 自定义监控命令
    var terminalTitle: String? // 终端窗口标题
}
