import SwiftUI
import AppKit

struct ContentView: View {
    private enum SidebarItem: Hashable {
        case projects
        case monitor
        case updates

        var title: String {
            switch self {
            case .projects:
                return "项目"
            case .monitor:
                return "监控"
            case .updates:
                return "更新"
            }
        }

        var systemImage: String {
            switch self {
            case .projects:
                return "square.grid.2x2"
            case .monitor:
                return "waveform.path.ecg"
            case .updates:
                return "arrow.down.circle"
            }
        }
    }

    @StateObject private var projectViewModel = ProjectViewModel()
    @State private var sidebarSelection: SidebarItem = .projects
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String?
    @State private var remoteUpdate: Version?
    @State private var showUpdateAlert = false
    @State private var isInstallingUpdate = false
    @State private var installStatusMessage: String = ""
    @State private var installErrorMessage: String?
    @State private var showInstallErrorAlert = false
    @State private var isPresentingProjectEditor = false
    @State private var editingProject: Project?
    @AppStorage("autoCheckUpdateEnabled") private var autoCheckUpdateEnabled: Bool = true
    @AppStorage("lastUpdateCheckTime") private var lastUpdateCheckTime: Double = 0
    
    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label(SidebarItem.projects.title, systemImage: SidebarItem.projects.systemImage)
                    .tag(SidebarItem.projects)
                Label(SidebarItem.monitor.title, systemImage: SidebarItem.monitor.systemImage)
                    .tag(SidebarItem.monitor)
                Label(SidebarItem.updates.title, systemImage: SidebarItem.updates.systemImage)
                    .tag(SidebarItem.updates)
            }
            .listStyle(.sidebar)
            .navigationTitle("项目管理器")
        } detail: {
            Group {
                switch sidebarSelection {
                case .projects:
                    VStack(spacing: 0) {
                        ProjectListView(viewModel: projectViewModel, onEdit: { project in
                            editingProject = project
                            isPresentingProjectEditor = true
                        })

                        Divider()

                        LogView(logs: $projectViewModel.logs)
                            .frame(minHeight: 160)
                    }
                    .navigationTitle(SidebarItem.projects.title)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Menu {
                                Button("部署全部项目") {
                                    projectViewModel.deployAllProjects()
                                }
                                Button("启动全部项目") {
                                    projectViewModel.runAllProjects(action: "start")
                                }
                                Button("停止全部项目") {
                                    projectViewModel.runAllProjects(action: "stop")
                                }
                                Divider()
                                Button("刷新") {
                                    projectViewModel.loadProjects()
                                }
                            } label: {
                                Image(systemName: "bolt.horizontal")
                            }

                            Button {
                                editingProject = nil
                                isPresentingProjectEditor = true
                            } label: {
                                Image(systemName: "plus")
                            }

                            Button {
                                triggerUpdateCheck()
                            } label: {
                                if isCheckingUpdate {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                            }
                        }
                    }
                case .monitor:
                    MonitorCenterView(viewModel: projectViewModel)
                        .navigationTitle(SidebarItem.monitor.title)
                case .updates:
                    UpdatesView(
                        isCheckingUpdate: isCheckingUpdate,
                        updateMessage: updateMessage,
                        currentVersion: VersionManager.currentAppVersion(),
                        remoteUpdate: remoteUpdate,
                        autoCheckEnabled: autoCheckUpdateEnabled,
                        lastCheckedText: formattedLastUpdateCheckTime(),
                        onCheck: triggerUpdateCheck,
                        onToggleAutoCheck: { enabled in
                            autoCheckUpdateEnabled = enabled
                        },
                        onInstall: { remote in
                            beginInstall(remote: remote)
                        }
                    )
                    .navigationTitle(SidebarItem.updates.title)
                }
            }
            .alert(isPresented: $showUpdateAlert) {
                if let remote = remoteUpdate {
                    return Alert(
                        title: Text("发现新版本"),
                        message: Text(updateMessage ?? ""),
                        primaryButton: .default(Text("立即安装")) {
                            beginInstall(remote: remote)
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
            .alert(isPresented: $showInstallErrorAlert) {
                Alert(
                    title: Text("更新失败"),
                    message: Text(installErrorMessage ?? ""),
                    dismissButton: .default(Text("确定"))
                )
            }
            .sheet(isPresented: $isInstallingUpdate) {
                VStack(alignment: .leading, spacing: 16) {
                    ProgressView()
                    Text(installStatusMessage.isEmpty ? "处理中…" : installStatusMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
                .frame(minWidth: 420)
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
        .onAppear {
            maybeAutoCheckUpdate()
        }
    }
    
    private func triggerUpdateCheck() {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        lastUpdateCheckTime = Date().timeIntervalSince1970
        updateMessage = nil
        remoteUpdate = nil
        VersionManager.checkForUpdate { result in
            isCheckingUpdate = false
            switch result {
            case .noUpdate(let current):
                updateMessage = "当前版本 \(current) 已是最新版本。"
                remoteUpdate = nil
                showUpdateAlert = true
            case .updateAvailable(let current, let remote):
                let notes = remote.releaseNotes ?? ""
                updateMessage = "当前版本: \(current)\n最新版本: \(remote.version)\n\n\(notes)"
                remoteUpdate = remote
                showUpdateAlert = true
            case .failure(let message):
                updateMessage = "检查更新失败: \(message)"
                remoteUpdate = nil
                showUpdateAlert = true
            }
        }
    }

    private func beginInstall(remote: Version) {
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true
        installStatusMessage = "正在开始更新…"
        installErrorMessage = nil
        VersionManager.downloadAndInstall(remote: remote, progress: { message in
            installStatusMessage = message
        }, completion: { result in
            switch result {
            case .success:
                installStatusMessage = "安装完成，正在重启…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if isInstallingUpdate {
                        isInstallingUpdate = false
                    }
                }
            case .failure(let error):
                isInstallingUpdate = false
                let base = error.localizedDescription
                let extra = "如果已自动打开安装包窗口，可以将 YourApp.app 拖动到“应用程序”完成更新。"
                installErrorMessage = base.isEmpty ? extra : base + "\n\n" + extra
                showInstallErrorAlert = true
            }
        })
    }

    private func maybeAutoCheckUpdate() {
        guard autoCheckUpdateEnabled else { return }
        let now = Date().timeIntervalSince1970
        if lastUpdateCheckTime <= 0 || now - lastUpdateCheckTime > 6 * 3600 {
            triggerUpdateCheck()
        }
    }

    private func formattedLastUpdateCheckTime() -> String? {
        if lastUpdateCheckTime <= 0 {
            return nil
        }
        let date = Date(timeIntervalSince1970: lastUpdateCheckTime)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}

private struct UpdatesView: View {
    let isCheckingUpdate: Bool
    let updateMessage: String?
    let currentVersion: String
    let remoteUpdate: Version?
    let autoCheckEnabled: Bool
    let lastCheckedText: String?
    let onCheck: () -> Void
    let onToggleAutoCheck: (Bool) -> Void
    let onInstall: (Version) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("当前版本")
                    .font(.headline)
                Text(currentVersion)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Toggle("自动检查更新", isOn: .init(get: { autoCheckEnabled }, set: { onToggleAutoCheck($0) }))

            if let last = lastCheckedText {
                Text("上次检查时间：\(last)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("检查更新") {
                    onCheck()
                }
                .buttonStyle(.borderedProminent)

                if isCheckingUpdate {
                    ProgressView()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("检查结果")
                    .font(.headline)
                Text(updateMessage?.isEmpty == false ? (updateMessage ?? "") : "点击“检查更新”获取最新版本信息")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let remote = remoteUpdate {
                HStack(spacing: 12) {
                    Button("立即安装") {
                        onInstall(remote)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
    }
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

private struct MonitorCenterView: View {
    @ObservedObject var viewModel: ProjectViewModel
    @State private var selectedProjectId: String = ""

    private var selectedProject: Project? {
        guard !selectedProjectId.isEmpty else {
            return viewModel.projects.first
        }
        return viewModel.projects.first(where: { $0.id == selectedProjectId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.projects.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无项目")
                        .font(.title3)
                    Text("请先在“项目”页面添加至少一个项目")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("监控中心")
                        .font(.title3)
                    Spacer()
                    Picker("项目", selection: $selectedProjectId) {
                        ForEach(viewModel.projects) { project in
                            Text(project.name)
                                .tag(project.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }

                Divider()

                if let project = selectedProject {
                    ProjectMonitorView(project: project)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("请选择要监控的项目")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            if selectedProjectId.isEmpty, let first = viewModel.projects.first {
                selectedProjectId = first.id
            }
        }
    }
}
