import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var projectViewModel = ProjectViewModel()
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String?
    @State private var updateDownloadURL: URL?
    @State private var showUpdateAlert = false
    @State private var isPresentingProjectEditor = false
    @State private var editingProject: Project?
    
    var body: some View {
        NavigationStack {
            ProjectListView(viewModel: projectViewModel)
                .navigationTitle("项目管理器")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: {
                            editingProject = nil
                            isPresentingProjectEditor = true
                        }) {
                            Image(systemName: "plus")
                        }
                        Button(action: {
                            triggerUpdateCheck()
                        }) {
                            if isCheckingUpdate {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                    }
                }
                .alert(isPresented: $showUpdateAlert) {
                    if let url = updateDownloadURL {
                        return Alert(
                            title: Text("发现新版本"),
                            message: Text(updateMessage ?? ""),
                            primaryButton: .default(Text("下载更新")) {
                                NSWorkspace.shared.open(url)
                            },
                            secondaryButton: .cancel(Text("稍后"))
                        )
                    } else {
                        return Alert(
                            title: Text("检查更新"),
                            message: Text(updateMessage ?? ""),
                            dismissButton: .default(Text("确定"))
                        )
                    }
                }
                .sheet(isPresented: $isPresentingProjectEditor) {
                    ProjectEditorView(project: editingProject) { project in
                        if let existing = editingProject {
                            if let index = projectViewModel.projects.firstIndex(where: { $0.id == existing.id }) {
                                projectViewModel.projects[index] = project
                                ProjectRunner.saveProjects(projectViewModel.projects)
                            }
                        } else {
                            projectViewModel.addProject(project)
                        }
                    }
                }
        }
    }
    
    private func triggerUpdateCheck() {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        updateMessage = nil
        updateDownloadURL = nil
        VersionManager.checkForUpdate { result in
            isCheckingUpdate = false
            switch result {
            case .noUpdate(let current):
                updateMessage = "当前版本 \(current) 已是最新版本。"
                updateDownloadURL = nil
                showUpdateAlert = true
            case .updateAvailable(let current, let remote):
                let notes = remote.releaseNotes ?? ""
                updateMessage = "当前版本: \(current)\n最新版本: \(remote.version)\n\n\(notes)"
                if let url = URL(string: remote.url) {
                    updateDownloadURL = url
                } else {
                    updateDownloadURL = nil
                }
                showUpdateAlert = true
            case .failure(let message):
                updateMessage = "检查更新失败: \(message)"
                updateDownloadURL = nil
                showUpdateAlert = true
            }
        }
    }
}

#Preview {
    ContentView()
}

struct ProjectEditorView: View {
    var project: Project?
    var onSave: (Project) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var type: String = ""
    @State private var path: String = ""
    @State private var portsText: String = ""
    @State private var logPath: String = "app.log"
    @State private var deployScript: String = ""
    @State private var startScript: String = ""
    @State private var stopScript: String = ""
    @State private var needSudoDeploy = false
    @State private var needSudoStart = false
    @State private var needSudoStop = false
    
    init(project: Project?, onSave: @escaping (Project) -> Void) {
        self.project = project
        self.onSave = onSave
        _name = State(initialValue: project?.name ?? "")
        _type = State(initialValue: project?.type ?? "")
        _path = State(initialValue: project?.path ?? "")
        _portsText = State(initialValue: project?.ports.map { String($0) }.joined(separator: ", ") ?? "")
        _logPath = State(initialValue: project?.logPath ?? "app.log")
        _deployScript = State(initialValue: project?.scriptUrls?["deploy"] ?? "")
        _startScript = State(initialValue: project?.scriptUrls?["start"] ?? "")
        _stopScript = State(initialValue: project?.scriptUrls?["stop"] ?? "")
        _needSudoDeploy = State(initialValue: project?.needsSudo?["deploy"] ?? false)
        _needSudoStart = State(initialValue: project?.needsSudo?["start"] ?? false)
        _needSudoStop = State(initialValue: project?.needsSudo?["stop"] ?? false)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project == nil ? "新增项目" : "编辑项目")
                .font(.title2)
            
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("类型", text: $type)
                    TextField("路径", text: $path)
                    TextField("端口，例如 3000, 8080", text: $portsText)
                    TextField("日志文件相对路径", text: $logPath)
                }
                Section("脚本 URL") {
                    TextField("部署脚本 URL", text: $deployScript)
                    TextField("启动脚本 URL", text: $startScript)
                    TextField("停止脚本 URL", text: $stopScript)
                }
                Section("管理员权限") {
                    Toggle("部署需要管理员权限", isOn: $needSudoDeploy)
                    Toggle("启动需要管理员权限", isOn: $needSudoStart)
                    Toggle("停止需要管理员权限", isOn: $needSudoStop)
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    let ports = portsText
                        .split { $0 == "," || $0 == " " }
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    var scriptUrls: [String: String] = [:]
                    if !deployScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        scriptUrls["deploy"] = deployScript.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if !startScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        scriptUrls["start"] = startScript.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if !stopScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        scriptUrls["stop"] = stopScript.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    var needsSudo: [String: Bool] = [:]
                    if needSudoDeploy { needsSudo["deploy"] = true }
                    if needSudoStart { needsSudo["start"] = true }
                    if needSudoStop { needsSudo["stop"] = true }
                    let newProject = Project(
                        id: project?.id ?? UUID().uuidString,
                        name: name,
                        type: type,
                        path: path,
                        ports: ports,
                        scripts: nil,
                        scriptUrls: scriptUrls.isEmpty ? nil : scriptUrls,
                        pid: project?.pid,
                        status: project?.status ?? "stopped",
                        logPath: logPath,
                        needsSudo: needsSudo.isEmpty ? nil : needsSudo
                    )
                    onSave(newProject)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 460)
    }
}
