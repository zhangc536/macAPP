import Foundation

final class ShellRunner {
    static func run(command: String, workingDir: String?, onOutput: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        if let workingDir = workingDir {
            task.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { fileHandle in
            if let data = try? fileHandle.readToEnd(), let output = String(data: data, encoding: .utf8) {
                if !output.isEmpty {
                    onOutput(output)
                }
            }
        }
        
        task.terminationHandler = { task in
            onExit(task.terminationStatus)
        }
        
        do {
            try task.run()
        } catch {
            onOutput("Error: \(error)")
            onExit(1)
        }
    }
    
    static func runAsync(command: String, workingDir: String?, onOutput: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        DispatchQueue.global().async {
            run(command: command, workingDir: workingDir, onOutput: onOutput, onExit: onExit)
        }
    }
}
