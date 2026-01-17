import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectViewModel
    @State private var selectedProjectForMonitor: Project?
    
    var body: some View {
        VStack {
            // 批量操作按钮区域
            HStack {
                Button("Deploy All Projects") {
                    viewModel.deployAllProjects()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                Button("Start All Projects") {
                    viewModel.runAllProjects(action: "start")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("Stop All Projects") {
                    viewModel.runAllProjects(action: "stop")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            
            List(viewModel.projects) { project in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(project.name)
                            .font(.headline)
                        Spacer()
                        Text(project.status)
                            .font(.subheadline)
                            .foregroundColor(project.status == "running" ? .green : .red)
                    }
                    
                    Text("Type: \(project.type)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("Path: \(project.path)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Text("Ports: \(project.ports.map(String.init).joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 8) {
                        if project.status == "stopped" {
                            Button("Start") {
                                viewModel.startProject(project)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Stop") {
                                viewModel.stopProject(project)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        
                        Button("Deploy") {
                            viewModel.deployProject(project)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Monitor") {
                            selectedProjectForMonitor = project
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Logs") {
                            selectedProjectForMonitor = project
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }
            Divider()
            LogView(logs: $viewModel.logs)
                .frame(minHeight: 160)
        }
        .onAppear {
            viewModel.loadProjects()
        }
        .refreshable {
            viewModel.loadProjects()
        }
        .sheet(item: $selectedProjectForMonitor) { project in
            ProjectMonitorView(project: project)
        }
    }
}

#Preview {
    ProjectListView(viewModel: ProjectViewModel())
}

final class ProjectMonitorViewModel: ObservableObject {
    @Published var logText: String = ""
    @Published var portStatus: String = ""
    @Published var processes: [String] = []
    
    private let project: Project
    private var timer: Timer?
    
    init(project: Project) {
        self.project = project
        start()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refresh()
    }
    
    private func refresh() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let logText = self.readLog()
            let portStatus = self.checkPort()
            let processes = Monitor.listRunningProcesses(self.project)
            DispatchQueue.main.async {
                self.logText = logText
                self.portStatus = portStatus
                self.processes = processes
            }
        }
    }
    
    private func readLog() -> String {
        let path = "\(project.path)/\(project.logPath)"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Log file not found"
        }
        let lines = content.split(separator: "\n")
        let lastLines = lines.suffix(200)
        return lastLines.joined(separator: "\n")
    }
    
    private func checkPort() -> String {
        guard let port = project.ports.first else {
            return "No port configured"
        }
        let inUse = Monitor.checkPortInUse(port)
        return inUse ? "Port \(port) in use" : "Port \(port) not listening"
    }
}

struct ProjectMonitorView: View {
    let project: Project
    @StateObject private var viewModel: ProjectMonitorViewModel
    
    init(project: Project) {
        self.project = project
        _viewModel = StateObject(wrappedValue: ProjectMonitorViewModel(project: project))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title2)
                Text(project.path)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                if let port = project.ports.first {
                    Text("Port: \(port)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Port Status")
                    .font(.headline)
                Text(viewModel.portStatus)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Processes")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.processes.isEmpty {
                            Text("No running processes")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(viewModel.processes, id: \.self) { line in
                                Text(line)
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Logs")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.logText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}
