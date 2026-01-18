import SwiftUI
import AppKit

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectViewModel
    @State private var selectedProjectForMonitor: Project?
    @State private var selectedProjectId: String?
    @State private var searchText: String = ""

    var onEdit: (Project) -> Void = { _ in }

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
        NavigationSplitView {
            List(selection: $selectedProjectId) {
                ForEach(filteredProjects) { project in
                    ProjectRow(project: project, statusText: displayStatus(project.status))
                        .tag(project.id)
                        .contextMenu {
                            if project.status == "running" {
                                Button("停止") {
                                    viewModel.stopProject(project)
                                }
                            } else {
                                Button("启动") {
                                    viewModel.startProject(project)
                                }
                            }
                            Button("部署") {
                                viewModel.deployProject(project)
                            }
                            Button("监控") {
                                selectedProjectForMonitor = project
                            }
                            if let launcherPath = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines), !launcherPath.isEmpty {
                                Button("打开启动文件") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: launcherPath))
                                }
                            }
                            Divider()
                            Button("编辑") {
                                onEdit(project)
                            }
                        }
                }
            }
            .searchable(text: $searchText, prompt: "搜索名称 / 类型 / 路径")
            .frame(minWidth: 320)
        } detail: {
            if let project = selectedProject {
                ProjectDetail(
                    project: project,
                    statusText: displayStatus(project.status),
                    onStart: { viewModel.startProject(project) },
                    onStop: { viewModel.stopProject(project) },
                    onDeploy: { viewModel.deployProject(project) },
                    onMonitor: { selectedProjectForMonitor = project },
                    onOpenLauncher: {
                        if let launcherPath = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines), !launcherPath.isEmpty {
                            NSWorkspace.shared.open(URL(fileURLWithPath: launcherPath))
                        }
                    },
                    onEdit: { onEdit(project) }
                )
            } else {
                VStack(spacing: 12) {
                    Text("请选择一个项目")
                        .font(.title3)
                    Text("在左侧选择项目后，可在此查看详情并执行操作")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private var filteredProjects: [Project] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.projects }
        return viewModel.projects.filter { project in
            project.name.lowercased().contains(q)
            || project.type.lowercased().contains(q)
            || (project.path ?? "").lowercased().contains(q)
        }
    }

    private var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return viewModel.projects.first(where: { $0.id == id })
    }
}

#Preview {
    ProjectListView(viewModel: ProjectViewModel())
}

private struct ProjectRow: View {
    let project: Project
    let statusText: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(project.status == "running" ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                Text("\(project.type)  •  \((project.ports ?? []).map(String.init).joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((project.status == "running" ? Color.green : Color.red).opacity(0.16))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct ProjectDetail: View {
    let project: Project
    let statusText: String
    let onStart: () -> Void
    let onStop: () -> Void
    let onDeploy: () -> Void
    let onMonitor: () -> Void
    let onOpenLauncher: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name)
                        .font(.title2)
                    Spacer()
                    Text(statusText)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((project.status == "running" ? Color.green : Color.red).opacity(0.16))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("类型", value: project.type)
                    LabeledContent("路径", value: project.path ?? "未配置")
                    if let firstPort = project.ports?.first {
                        LabeledContent("端口", value: String(firstPort))
                    } else {
                        LabeledContent("端口", value: "未配置")
                    }

                    let launcher = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    LabeledContent("启动文件", value: launcher.isEmpty ? "未捕获" : URL(fileURLWithPath: launcher).lastPathComponent)
                }
                .textSelection(.enabled)

                HStack(spacing: 10) {
                    if project.status == "running" {
                        Button("停止", action: onStop)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    } else {
                        Button("启动", action: onStart)
                            .buttonStyle(.borderedProminent)
                    }

                    Button("部署", action: onDeploy)
                        .buttonStyle(.bordered)

                    Button("监控", action: onMonitor)
                        .buttonStyle(.bordered)

                    if let launcherPath = project.launcherPath?.trimmingCharacters(in: .whitespacesAndNewlines), !launcherPath.isEmpty {
                        Button("启动文件", action: onOpenLauncher)
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button("编辑", action: onEdit)
                        .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

final class ProjectMonitorViewModel: ObservableObject {
    @Published var logText: String = ""
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
            let processes = Monitor.listRunningProcesses(self.project)
            DispatchQueue.main.async {
                self.logText = logText
                self.processes = processes
            }
        }
    }
    
    private func readLog() -> String {
        Monitor.readRecentLogs(project, tail: 200)
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
                Text(project.path ?? "未配置路径")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                if let port = project.ports?.first {
                    Text("端口：\(port)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
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
