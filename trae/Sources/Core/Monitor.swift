import Foundation

final class Monitor {
    private static func isDockerProject(_ project: Project) -> Bool {
        project.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "docker"
    }

    private static func dockerCandidateNames(_ project: Project) -> [String] {
        let raw = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let dashed = raw.replacingOccurrences(of: " ", with: "-")
        let underscored = raw.replacingOccurrences(of: " ", with: "_")
        return [
            project.id,
            raw,
            dashed,
            underscored
        ].filter { !$0.isEmpty }
    }

    private static func resolveDockerContainer(_ project: Project) -> String? {
        var names: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        let script = "command -v docker >/dev/null 2>&1 || exit 0; docker ps -a --format '{{.Names}}'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
            names = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }, onExit: { _ in
            semaphore.signal()
        })
        semaphore.wait()

        let candidates = dockerCandidateNames(project)
        for candidate in candidates {
            if names.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func isDockerContainerRunning(_ project: Project) -> Bool {
        guard isDockerProject(project) else { return false }
        guard let container = resolveDockerContainer(project) else { return false }

        var running = false
        let semaphore = DispatchSemaphore(value: 0)
        let script = "docker inspect -f '{{.State.Running}}' \(shellQuote(container)) 2>/dev/null"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
            running = output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }, onExit: { _ in
            semaphore.signal()
        })
        semaphore.wait()
        return running
    }

    static func openTerminalForProject(_ project: Project) {
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Monitoring \(project.name) ===\"\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorLog(_ project: Project, logPath: String? = nil) {
        if isDockerProject(project), let container = resolveDockerContainer(project) {
            let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"echo === Docker Logs - \(project.name) ===; docker logs -f --tail 200 \(shellQuote(container))\"' -e 'activate' -e 'end tell'"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
            return
        }

        let actualLogPath = logPath ?? project.logPath
        let basePath = project.path ?? ""
        let fullLogPath = basePath.isEmpty ? actualLogPath : "\(basePath)/\(actualLogPath)"
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Log Monitoring - \(project.name) ===\"; tail -f \(fullLogPath)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorPort(_ project: Project, port: Int? = nil) {
        let actualPort = port ?? (project.ports?.first ?? 0)
        if isDockerProject(project), let container = resolveDockerContainer(project) {
            let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"echo === Docker Port - \(project.name) ===; while true; do docker port \(shellQuote(container)) 2>/dev/null || echo 容器未运行或不存在; echo; echo Host lsof :\(actualPort); lsof -i :\(actualPort) 2>/dev/null || echo Not listening; sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
            return
        }
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Port \(actualPort) Monitoring - \(project.name) ===\"; while true; do lsof -i :\(actualPort); sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorProcess(_ project: Project, pid: Int? = nil) {
        if isDockerProject(project), let container = resolveDockerContainer(project) {
            let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"echo === Docker Processes - \(project.name) ===; while true; do docker stats --no-stream --format 'table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}' \(shellQuote(container)) 2>/dev/null || echo 容器未运行或不存在; echo; docker top \(shellQuote(container)) -eo pid,ppid,cmd 2>/dev/null || true; sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
            return
        }

        guard let actualPid = pid ?? project.pid else {
            return
        }
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Process \(actualPid) Monitoring - \(project.name) ===\"; while true; do ps -p \(actualPid) -o %cpu,%mem,command; sleep 1; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorProject(_ project: Project) {
        if isDockerProject(project), let container = resolveDockerContainer(project) {
            let actualPort = project.ports?.first ?? 0
            let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"echo === Docker Comprehensive - \(project.name) ===; while true; do echo [$(date +%H:%M:%S)] Container: \(container); docker inspect -f 'Status: {{.State.Status}}  Running: {{.State.Running}}  StartedAt: {{.State.StartedAt}}' \(shellQuote(container)) 2>/dev/null || echo 容器不存在; echo; docker stats --no-stream --format 'table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.NetIO}}\\t{{.BlockIO}}' \(shellQuote(container)) 2>/dev/null || true; echo; echo Ports:; docker port \(shellQuote(container)) 2>/dev/null || true; echo; echo Host lsof :\(actualPort); lsof -i :\(actualPort) 2>/dev/null || echo Not listening; echo; echo Top:; docker top \(shellQuote(container)) -eo pid,ppid,cmd 2>/dev/null || true; echo; echo Logs (tail 50):; docker logs --tail 50 \(shellQuote(container)) 2>/dev/null || true; sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
            return
        }

        // 综合监控：进程、端口、日志
        let port = project.ports?.first ?? 0
        let logPath = project.logPath
        let basePath = project.path ?? ""
        let fullLogPath = basePath.isEmpty ? logPath : "\(basePath)/\(logPath)"
        
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Comprehensive Monitoring - \(project.name) ===\"; while true; do echo \"[$(date +%H:%M:%S)] Process: \"; if [ -n \"\(project.pid ?? 0)\" ]; then ps -p \(project.pid ?? 0) -o %cpu,%mem,command; else echo \"Not running\"; fi; echo; echo \"Port: \(port): \"; lsof -i :\(port) 2>/dev/null || echo \"Not listening\"; echo; echo \"Recent Logs (last 5 lines): \"; tail -n 5 \(fullLogPath) 2>/dev/null || echo \"Log file not found\"; echo; sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorDirectory(_ project: Project, directory: String = ".") {
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Directory Monitoring - \(project.name) ===\"; watch -n 1 ls -la \(directory)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func monitorNetwork(_ project: Project) {
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== Network Monitoring - \(project.name) ===\"; while true; do echo \"Listening Ports: \"; netstat -an | grep LISTEN; sleep 3; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func customMonitor(_ project: Project, command: String, title: String) {
        let basePath = project.path ?? ""
        let cdPart = basePath.isEmpty ? "" : "cd \(basePath); "
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"\(cdPart)echo \"=== \(title) - \(project.name) ===\"; \(command)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
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
        ShellRunner.run(command: script, workingDir: nil, onOutput: { _ in }, onExit: { _ in })
    }
    
    static func listRunningProcesses(_ project: Project) -> [String] {
        if isDockerProject(project) {
            guard let container = resolveDockerContainer(project) else {
                return ["未找到 Docker 容器（尝试匹配项目 id / 名称失败）"]
            }

            var processes: [String] = []
            let semaphore = DispatchSemaphore(value: 0)
            let script = "docker top \(shellQuote(container)) -eo pid,ppid,cmd 2>/dev/null"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
                let lines = output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                processes = lines
            }, onExit: { _ in
                semaphore.signal()
            })
            semaphore.wait()
            let cleaned = processes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if cleaned.isEmpty {
                return ["容器未运行或无进程信息"]
            }
            if cleaned.count <= 1 {
                return ["容器正在运行，但未返回进程列表"]
            }
            return cleaned
        }

        var processes: [String] = []

        if let pid = project.pid, pid > 0 {
            let semaphore = DispatchSemaphore(value: 0)
            let script = "ps -p \(pid) -o pid,ppid,command 2>/dev/null | sed '1d'"

            ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
                processes = output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }, onExit: { _ in
                semaphore.signal()
            })
            semaphore.wait()
            return processes
        }

        var candidates = [project.id, project.name, project.type]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if project.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nexus" {
            candidates.append("nexus-network")
            candidates.append(".nexus/bin/nexus-network")
            candidates.append("nexus-network start")
            candidates.append("nexus.command")
            candidates.append("nexus.sh")
        }

        guard !candidates.isEmpty else {
            return []
        }

        for keyword in candidates {
            let semaphore = DispatchSemaphore(value: 0)
            var current: [String] = []

            let script = """
            key=\(shellQuote(keyword));
            if command -v pgrep >/dev/null 2>&1; then
              pids=$(pgrep -if "$key" || true);
            else
              pids="";
            fi;
            if [ -n "$pids" ]; then
              ps -p $pids -o pid,ppid,command 2>/dev/null | sed '1d'
            else
              ps -axo pid,ppid,command 2>/dev/null | grep -i "$key" | grep -v grep || true
            fi
            """

            ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
                current = output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }, onExit: { _ in
                semaphore.signal()
            })

            semaphore.wait()

            if !current.isEmpty {
                processes = current
                break
            }
        }

        return processes
    }

    static func readRecentLogs(_ project: Project, tail: Int = 200) -> String {
        if isDockerProject(project) {
            guard let container = resolveDockerContainer(project) else {
                return "未找到 Docker 容器（尝试匹配项目 id / 名称失败）"
            }

            var text = ""
            let semaphore = DispatchSemaphore(value: 0)
            let script = "docker logs --tail \(tail) \(shellQuote(container)) 2>/dev/null"
            ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
                text += output
            }, onExit: { _ in
                semaphore.signal()
            })
            semaphore.wait()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "暂无日志或容器未运行" : trimmed
        }

        guard let basePath = project.path, !basePath.isEmpty else {
            return "未配置项目路径"
        }
        let path = "\(basePath)/\(project.logPath)"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "未找到日志文件"
        }
        let lines = content.split(separator: "\n")
        let lastLines = lines.suffix(tail)
        return lastLines.joined(separator: "\n")
    }

    static func portStatusText(_ project: Project) -> String {
        guard let port = project.ports?.first else {
            return "未配置端口"
        }
        if isDockerProject(project) {
            guard let container = resolveDockerContainer(project) else {
                return "未找到 Docker 容器（尝试匹配项目 id / 名称失败）"
            }

            var text = ""
            let semaphore = DispatchSemaphore(value: 0)
            let script = """
            echo "docker port:";
            docker port \(shellQuote(container)) 2>/dev/null || echo "容器未运行或不存在";
            echo;
            if lsof -i :\(port) >/dev/null 2>&1; then
              echo "host 端口 \(port) 正在使用";
            else
              echo "host 端口 \(port) 未监听";
            fi
            """
            ShellRunner.run(command: script, workingDir: nil, onOutput: { output in
                text += output
            }, onExit: { _ in
                semaphore.signal()
            })
            semaphore.wait()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let inUse = checkPortInUse(port)
        return inUse ? "端口 \(port) 正在使用" : "端口 \(port) 未监听"
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

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
