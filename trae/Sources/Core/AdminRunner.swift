import Foundation

final class AdminRunner {
    static func run(command: String, onOutput: @escaping (String) -> Void = { _ in }, onExit: @escaping (Int32) -> Void = { _ in }) {
        // 使用 AppleScript 执行 sudo 命令，触发系统授权弹窗
        let appleScript = "do shell script \"\(command)\" with administrator privileges"
        let scriptCommand = "osascript -e '\(appleScript)'"
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", scriptCommand]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { fileHandle in
            if let data = try? fileHandle.readToEnd(), let output = String(data: data, encoding: .utf8) {
                onOutput(output)
            }
        }
        
        do {
            try task.run()
            task.waitUntilExit()
            onExit(task.terminationStatus)
        } catch {
            onOutput("Admin Error: \(error)")
            onExit(1)
        }
    }
    
    static func runAsync(command: String, onOutput: @escaping (String) -> Void = { _ in }, onExit: @escaping (Int32) -> Void = { _ in }) {
        DispatchQueue.global().async {
            run(command: command, onOutput: onOutput, onExit: onExit)
        }
    }
}
