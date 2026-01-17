import Foundation

final class ProjectRunner {
    static func run(project: Project, action: String, onLog: @escaping (String) -> Void) {
        if let scriptUrl = project.scriptUrls?[action] {
            let command = "bash <(curl -fsSL \(scriptUrl))"
            
            // 判断是否需要sudo权限
            let needSudo = project.needsSudo?[action] ?? false
            
            if needSudo {
                onLog("Executing admin command: \(command)")
                AdminRunner.run(command: command, onOutput: onLog, onExit: { status in
                    onLog("Admin command completed with status: \(status)")
                    if status == 0 {
                        updateProjectStatus(project: project, status: action == "stop" ? "stopped" : "running")
                    }
                })
            } else {
                onLog("Executing command: \(command)")
                ShellRunner.run(command: command, workingDir: project.path, onOutput: onLog, onExit: { status in
                    onLog("Command completed with status: \(status)")
                    if status == 0 {
                        updateProjectStatus(project: project, status: action == "stop" ? "stopped" : "running")
                    }
                })
            }
        } else {
            onLog("Error: Script URL not found for action: \(action)")
        }
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
        
        // 检查端口是否被占用
        if let port = project.ports.first {
            let isInUse = Monitor.checkPortInUse(port)
            if isInUse {
                status = "running"
            }
        }
        
        // 检查进程是否在运行
        let processes = Monitor.listRunningProcesses(project)
        if !processes.isEmpty {
            status = "running"
            if let firstProcess = processes.first {
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
            for project in projects {
                DispatchQueue.main.async {
                    onLog("Starting deployment for project: \(project.name)")
                }
                
                // 在单独的队列中运行每个项目的部署
                let group = DispatchGroup()
                group.enter()
                
                DispatchQueue.global().async {
                    deploy(project: project) { log in
                        DispatchQueue.main.async {
                            onLog(log)
                        }
                    }
                    group.leave()
                }
                
                // 等待当前项目部署完成后再继续下一个
                group.wait()
                
                // 添加短暂延迟以避免资源冲突
                Thread.sleep(forTimeInterval: 1.0)
            }
            
            DispatchQueue.main.async {
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
