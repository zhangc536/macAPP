# macOS 原生 App 开发计划（终端监控版）

## 一、项目结构

1. 创建主目录结构：
   - `trae/` - Trae 完全管理目录
   - `build/` - 编译输出目录
   - `dmg/` - DMG 打包脚本
   - `docs/` - 文档目录
   - `Package.swift` - Swift Package Manager 配置

2. 创建 trae 子目录：
   - `trae/Sources/` - Swift 源码
     - `AppMain/` - 应用主入口
     - `Core/` - 核心模块
     - `Views/` - SwiftUI 页面
     - `ViewModels/` - 视图模型
     - `Models/` - 数据模型
   - `trae/Resources/` - 资源文件
     - `projects.json` - 项目配置
     - `version.json` - App 更新信息

## 二、核心实现方案

### 1. 构建系统
- 使用 Swift Package Manager (SPM) 替代 Xcode
- 创建 Package.swift 配置文件，定义依赖和目标
- 使用 `swift build` 和 `swift run` 命令编译和运行

### 2. 终端监控实现

#### 2.1 核心功能
- 直接打开终端窗口执行监控命令
- 支持多种监控类型：
  - 日志监控：`tail -f app.log`
  - 端口监控：`lsof -i :PORT`
  - 进程监控：`ps -p PID -o %cpu,%mem,command`
  - 综合监控：自定义监控脚本
- 终端窗口管理：
  - 自动定位到项目目录
  - 支持多个终端窗口同时监控
  - 窗口标题显示项目名称和监控类型

#### 2.2 Monitor.swift 核心实现
```swift
final class Monitor {
    static func openTerminalForProject(_ project: Project) {
        // 打开终端窗口并切换到项目目录
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Monitoring \(project.name) ===\"\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorLog(_ project: Project, logPath: String) {
        let fullLogPath = "\(project.path)/\(logPath)"
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Log Monitoring - \(project.name) ===\"; tail -f \(fullLogPath)\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorPort(_ project: Project, port: Int) {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Port \(port) Monitoring - \(project.name) ===\"; while true; do lsof -i :\(port); sleep 2; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorProcess(_ project: Project, pid: Int) {
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Process \(pid) Monitoring - \(project.name) ===\"; while true; do ps -p \(pid) -o %cpu,%mem,command; sleep 1; clear; done\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
    
    static func monitorProject(_ project: Project) {
        // 综合监控：进程、端口、日志
        let script = "osascript -e 'tell application \"Terminal\"' -e 'do script \"cd \(project.path); echo \"=== Comprehensive Monitoring - \(project.name) ===\"; echo \"Process: \"; ps -p \(project.pid ?? 0) -o %cpu,%mem,command; echo \"Port: \"; lsof -i :\(project.ports.first ?? 0); echo \"Log (last 10 lines): \"; tail -n 10 app.log\"' -e 'activate' -e 'end tell'"
        ShellRunner.run(command: script, workingDir: nil, onOutput: {}, onExit: { _ in })
    }
}
```

### 3. 核心模块实现

#### 3.1 ShellRunner.swift
```swift
final class ShellRunner {
    static func run(command: String, workingDir: String?, onOutput: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        // 执行普通权限 shell 命令
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        if let workingDir = workingDir {
            task.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { fileHandle in
            if let data = try? fileHandle.readToEnd(), let output = String(data: data, encoding: .utf8) {
                onOutput(output)
            }
        }
        
        do {
            try task.run()
            task.waitUntilExit()
            onExit(task.terminationStatus)
        } catch {
            onOutput("Error: \(error)")
            onExit(1)
        }
    }
}
```

#### 3.2 AdminRunner.swift
```swift
final class AdminRunner {
    static func run(command: String) {
        // 使用 AppleScript 执行 sudo 命令，触发系统授权弹窗
        let script = "osascript -e 'do shell script \"\(command)\" with administrator privileges'"
        let task = Process()
        task.arguments = ["-c", script]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Admin command error: \(error)")
        }
    }
}
```

#### 3.3 ProjectRunner.swift
```swift
final class ProjectRunner {
    static func run(project: Project, action: String, needAdmin: Bool, onLog: @escaping (String) -> Void) {
        guard let scriptPath = project.scripts[action] else {
            onLog("Error: Script not found for action: \(action)")
            return
        }
        
        let fullScriptPath = Bundle.main.resourcePath! + "/scripts/" + scriptPath
        let command = "bash \(fullScriptPath)"
        
        if needAdmin {
            onLog("Executing admin command: \(command)")
            AdminRunner.run(command: command)
            onLog("Admin command completed")
        } else {
            onLog("Executing command: \(command)")
            ShellRunner.run(command: command, workingDir: project.path, onOutput: onLog, onExit: { status in
                onLog("Command completed with status: \(status)")
            })
        }
    }
}
```

#### 3.4 Project.swift
```swift
struct Project: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var path: String
    var ports: [Int]
    var scripts: [String: String]
    var pid: Int?
    var status: String = "stopped"
    var logPath: String = "app.log"
}
```

### 4. SwiftUI 视图设计

#### 4.1 ProjectListView.swift
```swift
struct ProjectListView: View {
    @StateObject var viewModel = ProjectViewModel()
    
    var body: some View {
        List(viewModel.projects) { project in
            VStack(alignment: .leading) {
                Text(project.name)
                    .font(.headline)
                Text("Status: \(project.status)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text("Ports: \(project.ports.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                HStack {
                    Button("Start") { viewModel.startProject(project) }
                    Button("Stop") { viewModel.stopProject(project) }
                    Button("Deploy") { viewModel.deployProject(project) }
                    Button("Monitor Terminal") { viewModel.openTerminalMonitor(project) }
                    Button("Log Terminal") { viewModel.openLogTerminal(project) }
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
        .onAppear { viewModel.loadProjects() }
    }
}
```

#### 4.2 ProjectViewModel.swift
```swift
class ProjectViewModel: ObservableObject {
    @Published var projects: [Project] = []
    
    func loadProjects() {
        // 从 projects.json 加载项目配置
    }
    
    func startProject(_ project: Project) {
        // 启动项目
    }
    
    func stopProject(_ project: Project) {
        // 停止项目
    }
    
    func deployProject(_ project: Project) {
        // 部署项目
    }
    
    func openTerminalMonitor(_ project: Project) {
        Monitor.monitorProject(project)
    }
    
    func openLogTerminal(_ project: Project) {
        Monitor.monitorLog(project, logPath: project.logPath)
    }
    
    func openPortTerminal(_ project: Project, port: Int) {
        Monitor.monitorPort(project, port: port)
    }
}
```

### 5. 监控类型和对应命令

| 监控类型 | 命令示例 | 说明 |
|---------|---------|------|
| 日志监控 | `tail -f app.log` | 实时显示日志文件内容 |
| 端口监控 | `lsof -i :8080` | 查看端口占用情况 |
| 进程监控 | `ps -p 1234 -o %cpu,%mem,command` | 查看特定进程的 CPU/内存使用 |
| 综合监控 | 自定义脚本 | 同时显示进程、端口、日志信息 |
| 目录监控 | `watch -n 1 ls -la` | 定时刷新目录内容 |
| 网络监控 | `netstat -an | grep LISTEN` | 查看监听端口 |

### 6. 终端窗口管理

- 使用 AppleScript 自动打开终端窗口：`osascript -e 'tell application "Terminal"' -e 'do script "command"' -e 'activate' -e 'end tell'`
- 支持自定义终端窗口标题：`osascript -e 'tell application "Terminal"' -e 'set custom title of window 1 to "Project Monitor"' -e 'end tell'`
- 支持分屏终端：`osascript -e 'tell application "Terminal"' -e 'tell window 1 to split vertically with default profile' -e 'end tell'`
- 支持终端主题设置：`osascript -e 'tell application "Terminal"' -e 'set current settings of window 1 to settings set "Pro"' -e 'end tell'`

## 三、编译与打包流程

1. **编译 App**：
   ```bash
   swift build -c release --arch arm64 --arch x86_64
   ```

2. **生成 App 包**：
   - 创建 .app 目录结构
   - 复制编译产物和资源文件
   - 创建 Info.plist 和 PkgInfo

3. **DMG 打包**：
   - 使用 create-dmg 工具
   - 自动生成 DMG 安装包
   - 支持拖放安装到 Applications

## 四、关键脚本

### 1. 编译脚本 (build_app.sh)
```bash
#!/bin/bash

# 清理旧构建产物
rm -rf build/

# 编译多架构二进制
swift build -c release --arch arm64 --arch x86_64

# 创建 .app 目录结构
mkdir -p build/YourApp.app/Contents/MacOSkdir -p build/YourApp.app/Contents/Resources

# 复制编译产物
cp .build/apple/Products/Release/YourApp build/YourApp.app/Contents/MacOS/

# 复制资源文件
cp -r trae/Resources/* build/YourApp.app/Contents/Resources/

# 创建 Info.plist
cat > build/YourApp.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>YourApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourapp.YourApp</string>
    <key>CFBundleName</key>
    <string>YourApp</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to control Terminal to display monitoring information.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>This app needs access to the desktop folder for saving files.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>This app needs access to the documents folder for saving files.</string>
    <key>NSFullDiskAccessUsageDescription</key>
    <string>This app needs full disk access to monitor processes and files.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>This app needs administrator privileges for system tasks like installing Docker.</string>
</dict>
</plist>
EOF

# 创建 PkgInfo
echo -n "APPL????" > build/YourApp.app/Contents/PkgInfo

# 设置执行权限
chmod +x build/YourApp.app/Contents/MacOS/YourApp

# 复制脚本文件
mkdir -p build/YourApp.app/Contents/Resources/scripts
cp -r trae/Resources/scripts/* build/YourApp.app/Contents/Resources/scripts/
chmod +x build/YourApp.app/Contents/Resources/scripts/*/*/*.sh
```

### 2. DMG 打包脚本 (dmg/build_dmg.sh)
```bash
#!/bin/bash

# 确保 create-dmg 已安装
if ! command -v create-dmg &> /dev/null; then
    echo "create-dmg not found. Installing..."
    brew install create-dmg
fi

# 清理旧 DMG
rm -f dmg/YourApp.dmg

# 创建 DMG
create-dmg \
  --volname "YourApp Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --app-drop-link 500 200 \
  --hide-extension "YourApp.app" \
  --icon-size 100 \
  --icon "YourApp.app" 100 200 \
  build/YourApp.app \
  dmg/
```

## 五、更新机制

- 读取 version.json 检查 App 更新
- 支持检查脚本配置更新
- 下载新 DMG 并提示用户安装
- 支持 App 和项目更新

## 六、权限策略

- sudo 仅限系统准备操作（如 Docker 安装）
- 项目运行使用普通权限
- 首次运行需要右键 → 打开 → 系统授权弹窗
- 终端控制需要 NSAppleEventsUsageDescription 权限
- 监控需要 NSFullDiskAccessUsageDescription 权限

## 七、实现步骤

1. 初始化 SPM 项目结构
2. 实现核心模块（Project、ShellRunner、AdminRunner 等）
3. 实现终端监控功能
4. 开发 SwiftUI 视图
5. 编写编译和打包脚本
6. 实现更新机制
7. 测试和调试
8. 生成 DMG 安装包

## 八、技术栈

- Swift 5.9+
- SwiftUI
- Swift Package Manager
- Shell 脚本
- AppleScript
- create-dmg 工具

## 九、优势

- 完全摆脱 Xcode 依赖
- 使用 SPM 简化项目管理
- 命令行驱动的开发流程
- 终端监控直观、实时
- 支持多种监控类型
- 终端窗口可自定义配置
- 支持多平台架构（arm64 + x86_64）

## 十、终端监控使用流程

1. 用户在 SwiftUI 界面选择项目
2. 点击"Monitor Terminal"按钮
3. 系统自动打开终端窗口
4. 终端窗口显示项目监控信息
5. 用户可在终端中直接查看和交互
6. 支持多个终端窗口同时监控不同项目
7. 终端窗口可手动关闭，不影响 App 运行

## 十一、扩展功能

- 支持自定义监控命令
- 支持终端主题切换
- 支持监控配置保存
- 支持监控历史记录
- 支持远程监控功能
- 支持监控告警通知