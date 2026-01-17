import Foundation

final class Monitor {
    static func openTerminalForProject(_ project: Project) {
        // 打开终端窗口并切换到项目目录
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Monitoring \(project.name) ===\"\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorLog(_ project: Project, logPath: String? = nil) {
        let actualLogPath = logPath ?? project.logPath
        let fullLogPath = "\(project.path)/\(actualLogPath)"
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Log Monitoring - \(project.name) ===\"; tail -f \(fullLogPath)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorPort(_ project: Project, port: Int? = nil) {
        let actualPort = port ?? project.ports.first ?? 0
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Port \(actualPort) Monitoring - \(project.name) ===\"; while true; do lsof -i :\(actualPort); sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorProcess(_ project: Project, pid: Int? = nil) {
        guard let actualPid = pid ?? project.pid else {
            return
        }
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Process \(actualPid) Monitoring - \(project.name) ===\"; while true; do ps -p \(actualPid) -o %cpu,%mem,command; sleep 1; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorProject(_ project: Project) {
        // 综合监控：进程、端口、日志
        let port = project.ports.first ?? 0
        let logPath = project.logPath
        let fullLogPath = "\(project.path)/\(logPath)"
        
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Comprehensive Monitoring - \(project.name) ===\"; while true; do echo \"[\$(date +%H:%M:%S)] Process: \"; if [ -n \"\(project.pid ?? 0)\" ]; then ps -p \(project.pid ?? 0) -o %cpu,%mem,command; else echo \"Not running\"; fi; echo; echo \"Port: \(port): \"; lsof -i :\(port) 2>/dev/null || echo \"Not listening\"; echo; echo \"Recent Logs (last 5 lines): \"; tail -n 5 \(fullLogPath) 2>/dev/null || echo \"Log file not found\"; echo; sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorDirectory(_ project: Project, directory: String = ".") {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Directory Monitoring - \(project.name) ===\"; watch -n 1 ls -la \(directory)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorNetwork(_ project: Project) {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Network Monitoring - \(project.name) ===\"; while true; do echo \"Listening Ports: \"; netstat -an | grep LISTEN; sleep 3; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func customMonitor(_ project: Project, command: String, title: String) {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== \(title) - \(project.name) ===\"; \(command)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorWithConfig(_ config: MonitorConfig, project: Project) {
        switch config.type {
        case .log:
            monitorLog(project, logPath: config.target)
        case .port:
            if let port = Int(config.target) {
                monitorPort(project, port: port)
            } else {
                monitorPort(project)
            }
        case .process:
            if let pid = Int(config.target) {
                monitorProcess(project, pid: pid)
            } else {
                monitorProcess(project)
            }
        case .comprehensive:
            monitorProject(project)
        case .directory:
            monitorDirectory(project, directory: config.target)
        case .network:
            monitorNetwork(project)
        }
    }
    
    static func closeAllTerminals() {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'close every window' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func listRunningProcesses(_ project: Project) -> [String] {
        var processes: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        let script = "ps aux | grep \"\(project.path)\" | grep -v grep"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
            processes = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        }, onExit: { _ in
            semaphore.signal()
        })
        
        semaphore.wait()
        return processes
    }
    
    static func checkPortInUse(_ port: Int) -> Bool {
        var isInUse = false
        let semaphore = DispatchSemaphore(value: 0)
        
        let script = "lsof -i :\(port) > /dev/null 2>&1; echo $?"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
            isInUse = output.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        }, onExit: { _ in
            semaphore.signal()
        })
        
        semaphore.wait()
        return isInUse
    }
}
