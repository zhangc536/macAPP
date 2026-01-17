import Foundation
import SwiftUI

class ProjectViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var logs: String = ""
    
    init() {
        loadProjects()
    }
    
    func loadProjects() {
        projects = ProjectRunner.loadProjects()
        // 检查每个项目的状态
        projects.forEach { project in
            checkProjectStatus(project)
        }
    }
    
    func checkProjectStatus(_ project: Project) {
        ProjectRunner.checkStatus(project: project) { status in
            DispatchQueue.main.async {
                if let index = self.projects.firstIndex(where: { $0.id == project.id }) {
                    self.projects[index].status = status
                }
            }
        }
    }
    
    func startProject(_ project: Project) {
        addLog("Starting project: \(project.name)...")
        ProjectRunner.start(project: project) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
    }
    
    func stopProject(_ project: Project) {
        addLog("Stopping project: \(project.name)...")
        ProjectRunner.stop(project: project) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
    }
    
    func deployProject(_ project: Project) {
        addLog("Deploying project: \(project.name)...")
        ProjectRunner.deploy(project: project) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
    }
    
    func deployAllProjects() {
        addLog("Starting deployment for all projects...")
        ProjectRunner.deployAll(projects: projects) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
    }
    
    func runAllProjects(action: String) {
        addLog("Running '\(action)' for all projects...")
        ProjectRunner.runAll(projects: projects, action: action) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
    }
    
    func openTerminalMonitor(_ project: Project) {
        Monitor.monitorProject(project)
        addLog("Opening terminal monitor for project: \(project.name)")
    }
    
    func openLogTerminal(_ project: Project) {
        Monitor.monitorLog(project)
        addLog("Opening log terminal for project: \(project.name)")
    }
    
    func openPortTerminal(_ project: Project, port: Int) {
        Monitor.monitorPort(project, port: port)
        addLog("Opening port monitor for project: \(project.name), port: \(port)")
    }
    
    func addProject(_ project: Project) {
        ProjectRunner.addProject(project)
        loadProjects()
        addLog("Added new project: \(project.name)")
    }
    
    func removeProject(_ project: Project) {
        ProjectRunner.removeProject(project)
        loadProjects()
        addLog("Removed project: \(project.name)")
    }
    
    private func addLog(_ log: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs += "[\(timestamp)] \(log)\n"
    }
    
    func clearLogs() {
        logs = ""
    }
}
