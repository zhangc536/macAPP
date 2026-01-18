import Foundation

final class ProjectRunner {
    static func run(project: Project, action: String, onLog: @escaping (String) -> Void) {
        if action == "start" {
            let launcherPath = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let captured = captureLauncherIfExists(project: project, onLog: onLog, logNotFound: launcherPath.isEmpty)
            let actualLauncherPath: String
            if let captured, !captured.isEmpty {
                actualLauncherPath = captured
            } else {
                actualLauncherPath = launcherPath
            }

            if actualLauncherPath.isEmpty {
                onLog("未找到启动文件，已禁止通过 URL 启动。")
                return
            }

            if openLauncher(path: actualLauncherPath, onLog: onLog) {
                updateProjectStatus(project: project, status: "running")
                return
            }

            if let recaptured = captureLauncherIfExists(project: project, onLog: onLog, logNotFound: true),
               openLauncher(path: recaptured, onLog: onLog) {
                updateProjectStatus(project: project, status: "running")
            }
            return
        }

        if action == "stop",
           project.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nexus",
           project.scriptUrls?["stop"] == nil {
            stopByKeyword(project: project, keyword: "nexus", onLog: onLog)
            return
        }

        if let scriptUrl = project.scriptUrls?[action] {
            let quotedURL = shellQuote(scriptUrl)
            let scriptCommand = "bash <(curl -fsSL \(quotedURL))"
            
            // 判断是否需要sudo权限
            let needSudo = project.needsSudo?[action] ?? false

            if action == "deploy", (project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty {
                if let captured = captureLauncherIfExists(project: project, onLog: onLog, logNotFound: false) {
                    onLog("检测到已存在启动文件，跳过部署：\(URL(fileURLWithPath: captured).lastPathComponent)")
                    return
                }
            }

            if action == "deploy", needSudo {
                onLog("部署前检查 Homebrew…")
                guard ensureHomebrewInstalled(onLog: onLog) else {
                    onLog("Homebrew 未就绪，已取消部署。")
                    return
                }

                onLog("执行部署（管理员权限）…")
                AdminRunner.run(command: scriptCommand, onOutput: onLog, onExit: { status in
                    onLog("部署完成，退出码: \(status)")
                    if status == 0 {
                        _ = captureLauncherIfExists(project: project, onLog: onLog, logNotFound: false)
                    }
                })
                return
            }
            
            if needSudo {
                onLog("执行管理员命令: \(scriptCommand)")
                AdminRunner.run(command: scriptCommand, onOutput: onLog, onExit: { status in
                    onLog("管理员命令完成，退出码: \(status)")
                    if status == 0 {
                        updateProjectStatus(project: project, status: action == "stop" ? "stopped" : "running")
                    }
                })
            } else {
                let finalCommand: String
                if action == "deploy" {
                    finalCommand = wrapWithHomebrewEnsure(scriptCommand)
                } else {
                    finalCommand = scriptCommand
                }

                onLog("执行命令: \(finalCommand)")
                ShellRunner.run(command: finalCommand, workingDir: project.path, onOutput: onLog, onExit: { status in
                    onLog("命令完成，退出码: \(status)")
                    if status == 0 {
                        updateProjectStatus(project: project, status: action == "stop" ? "stopped" : "running")
                        if action == "deploy" {
                            _ = captureLauncherIfExists(project: project, onLog: onLog, logNotFound: false)
                        }
                    }
                })
            }
        } else {
            onLog("错误：未找到对应脚本 URL（action=\(action)）")
        }
    }

    private static func openLauncher(path: String, onLog: @escaping (String) -> Void) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            onLog("启动文件不存在：\(path)")
            return false
        }

        let command = "/usr/bin/open \(shellQuote(path))"
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        ShellRunner.run(command: command, workingDir: nil, onOutput: { output in
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                onLog(text)
            }
        }, onExit: { status in
            ok = (status == 0)
            semaphore.signal()
        })
        semaphore.wait()
        if ok {
            onLog("已通过启动文件启动：\(URL(fileURLWithPath: path).lastPathComponent)")
        } else {
            onLog("启动文件启动失败：\(URL(fileURLWithPath: path).lastPathComponent)")
        }
        return ok
    }

    private static func captureLauncherIfExists(project: Project, onLog: @escaping (String) -> Void, logNotFound: Bool) -> String? {
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            onLog("未能获取桌面目录，无法捕获启动文件。")
            return nil
        }

        let candidates: [URL]
        do {
            candidates = try FileManager.default.contentsOfDirectory(
                at: desktopURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            onLog("读取桌面目录失败：\(error.localizedDescription)")
            return nil
        }

        let matched = candidates.compactMap { url -> (url: URL, mtime: Date)? in
            let baseName = url.deletingPathExtension().lastPathComponent
            let normalizedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let type = project.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let identifier = project.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var keywords: [String] = []
            if !name.isEmpty { keywords.append(name) }
            if !type.isEmpty { keywords.append(type) }
            if !identifier.isEmpty { keywords.append(identifier) }
            guard keywords.contains(where: { normalizedBase.contains($0) }) else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return (url, mtime)
        }
        .sorted { $0.mtime > $1.mtime }
        .first

        guard let found = matched?.url else {
            if logNotFound {
                onLog("未在桌面找到启动文件：\(project.name)(.*)")
            }
            return nil
        }

        let current = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current != found.path {
            saveLauncherPath(projectId: project.id, launcherPath: found.path)
            onLog("已捕获启动文件：\(found.lastPathComponent)")
        }
        return found.path
    }

    private static func stopByKeyword(project: Project, keyword: String, onLog: @escaping (String) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onLog("停止失败：关键字为空")
            return
        }
        let command = """
        key=\(shellQuote(trimmed));
        pids=$(pgrep -if "$key" || true);
        if [ -z "$pids" ]; then
          echo "未找到包含 $key 的进程";
          exit 0;
        fi;
        echo "即将终止进程: $pids";
        kill $pids || true;
        sleep 2;
        remain=$(pgrep -if "$key" || true);
        if [ -n "$remain" ]; then
          echo "部分进程未退出，强制结束: $remain";
          kill -9 $remain || true;
        fi;
        """
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        ShellRunner.run(command: command, workingDir: nil, onOutput: { output in
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                onLog(text)
            }
        }, onExit: { status in
            ok = (status == 0)
            semaphore.signal()
        })
        semaphore.wait()
        if ok {
            updateProjectStatus(project: project, status: "stopped")
        }
    }

    private static func saveLauncherPath(projectId: String, launcherPath: String) {
        var projects = loadProjects()
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].launcherPath = launcherPath
            saveProjects(projects)
        }
    }

    private static func ensureHomebrewInstalled(onLog: @escaping (String) -> Void) -> Bool {
        let command = """
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";
        if command -v brew >/dev/null 2>&1; then
          brew --version | head -n 1
          exit 0
        fi;
        echo "未检测到 Homebrew，开始安装…";
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)";
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";
        if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi;
        if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi;
        command -v brew >/dev/null 2>&1 || { echo "Homebrew 安装失败或未完成"; exit 1; };
        brew --version | head -n 1
        """

        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        ShellRunner.run(command: command, workingDir: nil, onOutput: { output in
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                onLog(text)
            }
        }, onExit: { status in
            ok = (status == 0)
            semaphore.signal()
        })
        semaphore.wait()
        return ok
    }

    private static func wrapWithHomebrewEnsure(_ inner: String) -> String {
        """
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";
        if ! command -v brew >/dev/null 2>&1; then
          echo "未检测到 Homebrew，开始安装…";
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)";
          export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";
          if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi;
          if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi;
        fi;
        command -v brew >/dev/null 2>&1 || { echo "Homebrew 未就绪，请先完成安装后重试"; exit 1; };
        \(inner)
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    static func runAsync(project: Project, action: String, onLog: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            run(project: project, action: action, onLog: onLog)
        }
    }
    
    static func deploy(project: Project, onLog: @escaping (String) -> Void) {
        run(project: project, action: "deploy", onLog: onLog)
    }
    
    static func start(project: Project, onLog: @escaping (String) -> Void) {
        run(project: project, action: "start", onLog: onLog)
    }
    
    static func stop(project: Project, onLog: @escaping (String) -> Void) {
        run(project: project, action: "stop", onLog: onLog)
    }
    
    static func install(project: Project, onLog: @escaping (String) -> Void) {
        run(project: project, action: "install", onLog: onLog)
    }
    
    static func update(project: Project, onLog: @escaping (String) -> Void) {
        run(project: project, action: "update", onLog: onLog)
    }
    
    static func checkStatus(project: Project, onStatus: @escaping (String) -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        var status = "stopped"

        if project.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "docker" {
            if Monitor.isDockerContainerRunning(project) {
                status = "running"
            }
            onStatus(status)
            updateProjectStatus(project: project, status: status)
            semaphore.signal()
            return
        }
        
        let processes = Monitor.listRunningProcesses(project)
        let runningLines = processes.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }
        if !runningLines.isEmpty {
            status = "running"
            if let firstProcess = runningLines.first {
                let parts = firstProcess
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                if parts.count >= 2, let pid = Int(parts[1]) {
                    updateProjectPid(project: project, pid: pid)
                }
            }
        }
        
        onStatus(status)
        updateProjectStatus(project: project, status: status)
        semaphore.signal()
    }
    
    static func updateProjectStatus(project: Project, status: String) {
        // 更新项目状态，这里可以实现持久化逻辑
        print("Project \(project.name) status updated to: \(status)")
    }
    
    static func updateProjectPid(project: Project, pid: Int) {
        // 更新项目PID，这里可以实现持久化逻辑
        print("Project \(project.name) PID updated to: \(pid)")
    }
    
    static func loadProjects() -> [Project] {
        guard let projectsPath = Bundle.main.path(forResource: "projects", ofType: "json") else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: projectsPath))
            let decoder = JSONDecoder()
            return try decoder.decode([Project].self, from: data)
        } catch {
            print("Error loading projects: \(error)")
            return []
        }
    }
    
    static func saveProjects(_ projects: [Project]) {
        guard let projectsPath = Bundle.main.path(forResource: "projects", ofType: "json") else {
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(projects)
            try data.write(to: URL(fileURLWithPath: projectsPath))
        } catch {
            print("Error saving projects: \(error)")
        }
    }
    
    static func addProject(_ project: Project) {
        var projects = loadProjects()
        projects.append(project)
        saveProjects(projects)
    }
    
    static func removeProject(_ project: Project) {
        var projects = loadProjects()
        projects.removeAll { $0.id == project.id }
        saveProjects(projects)
    }
    
    static func deployAll(projects: [Project], onLog: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                onLog("部署前检查 Homebrew…")
            }
            guard ensureHomebrewInstalled(onLog: { log in
                DispatchQueue.main.async {
                    onLog(log)
                }
            }) else {
                DispatchQueue.main.async {
                    onLog("Homebrew 未就绪，已取消全部部署。")
                }
                return
            }

            let group = DispatchGroup()
            for project in projects {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    DispatchQueue.main.async {
                        onLog("Starting deployment for project: \(project.name)")
                    }
                    deploy(project: project) { log in
                        DispatchQueue.main.async {
                            onLog(log)
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                onLog("All projects deployed successfully!")
            }
        }
    }
    
    static func runAll(projects: [Project], action: String, onLog: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            for project in projects {
                DispatchQueue.main.async {
                    onLog("Running '\(action)' for project: \(project.name)")
                }
                
                let group = DispatchGroup()
                group.enter()
                
                DispatchQueue.global().async {
                    run(project: project, action: action) { log in
                        DispatchQueue.main.async {
                            onLog(log)
                        }
                    }
                    group.leave()
                }
                
                group.wait()
                
                // 添加短暂延迟以避免资源冲突
                Thread.sleep(forTimeInterval: 1.0)
            }
            
            DispatchQueue.main.async {
                onLog("All projects completed '\(action)' action!")
            }
        }
    }
}
