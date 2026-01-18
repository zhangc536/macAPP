import SwiftUI
import AppKit

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectViewModel
    @State private var selectedProjectForMonitor: Project?

    private func displayStatus(_ status: String) -> String {
        switch status {
        case "running":
            return "运行中"
        case "stopped":
            return "已停止"
        default:
            return status
        }
    }
    
    var body: some View {
        VStack {
            // 批量操作按钮区域
            HStack {
                Button("部署全部项目") {
                    viewModel.deployAllProjects()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                Button("启动全部项目") {
                    viewModel.runAllProjects(action: "start")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("停止全部项目") {
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
                        Text(displayStatus(project.status))
                            .font(.subheadline)
                            .foregroundColor(project.status == "running" ? .green : .red)
                    }
                    
                    Text("类型：\(project.type)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("路径：\(project.path)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Text("端口：\(project.ports.map(String.init).joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 8) {
                        if project.status == "stopped" {
                            Button("启动") {
                                viewModel.startProject(project)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("停止") {
                                viewModel.stopProject(project)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        
                        Button("部署") {
                            viewModel.deployProject(project)
                        }
                        .buttonStyle(.bordered)
                        
                        if let launcherPath = project.launcherPath, !launcherPath.isEmpty {
                            Button("启动文件") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: launcherPath))
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("监控") {
                            selectedProjectForMonitor = project
                        }
                        .buttonStyle(.bordered)
                        
                        Button("日志") {
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
        Monitor.readRecentLogs(project, tail: 200)
    }
    
    private func checkPort() -> String {
        Monitor.portStatusText(project)
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
                    Text("端口：\(port)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("端口状态")
                    .font(.headline)
                Text(viewModel.portStatus)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("进程")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.processes.isEmpty {
                            Text("暂无运行中的进程")
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
                Text("日志")
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
