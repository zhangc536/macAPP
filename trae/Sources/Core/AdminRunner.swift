import Foundation

final class AdminRunner {
    static func run(command: String, onOutput: @escaping (String) -> Void = { _ in }, onExit: @escaping (Int32) -> Void = { _ in }) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", makeAppleScript(command: command)]
        
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

    private static func makeAppleScript(command: String) -> String {
        let normalized = command
            .replacingOccurrences(of: "\r\n", with: "; ")
            .replacingOccurrences(of: "\n", with: "; ")
            .replacingOccurrences(of: "\r", with: "; ")
        let escaped = normalized
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
