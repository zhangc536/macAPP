import Foundation
import SwiftUI

class ProjectViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var logs: String = ""
    private var statusTimer: Timer?
    
    init() {
        loadProjects()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentProjects = self.projects
            DispatchQueue.global(qos: .background).async {
                currentProjects.forEach { project in
                    self.checkProjectStatus(project)
                }
            }
        }
        if let timer = statusTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    func loadProjects() {
        projects = ProjectRunner.loadProjects()
        projects.forEach { project in
            DispatchQueue.global(qos: .background).async {
                self.checkProjectStatus(project)
            }
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
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
            self.checkProjectStatus(project)
        }
    }
    
    func stopProject(_ project: Project) {
        addLog("Stopping project: \(project.name)...")
        ProjectRunner.stop(project: project) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
        Monitor.closeAllTerminals()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
            self.checkProjectStatus(project)
        }
    }
    
    func deployProject(_ project: Project) {
        addLog("Deploying project: \(project.name)...")
        ProjectRunner.deploy(project: project) { log in
            DispatchQueue.main.async {
                self.addLog(log)
            }
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0) {
            self.checkProjectStatus(project)
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
