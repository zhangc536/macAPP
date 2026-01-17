import Foundation

// 简化的Project模型用于测试
struct Project: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var path: String
    var ports: [Int]
    var scripts: [String: String]?
    var scriptUrls: [String: String]?
    var pid: Int?
    var status: String = "stopped"
    var logPath: String = "app.log"
    var needsSudo: [String: Bool]?
}

// 模拟ProjectRunner的部分功能用于测试
class MockProjectRunner {
    static func deploy(project: Project, onLog: @escaping (String) -> Void) {
        onLog("Deploying project: \(project.name)")
        // 模拟部署过程
        usleep(500000) // 0.5秒延迟
        onLog("Project \(project.name) deployed successfully")
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
}

// 模拟主线程调度
class ThreadSafeLogger {
    private var logs: [String] = []
    private let queue = DispatchQueue(label: "logger", attributes: .concurrent)
    
    func addLog(_ log: String) {
        queue.async(flags: .barrier) {
            self.logs.append(log)
            print(log)
        }
    }
    
    func getLogs() -> [String] {
        var result: [String] = []
        queue.sync {
            result = self.logs
        }
        return result
    }
}

let logger = ThreadSafeLogger()

// 创建测试项目
let projects = [
    Project(id: "1", name: "Docker Demo", type: "docker", path: "/Users/xxx/docker-app", ports: [8080], 
            scriptUrls: ["deploy": "https://raw.githubusercontent.com/zhangc536/ritual-ubuntn/refs/heads/main/deploy.sh"]),
    Project(id: "2", name: "Python Service", type: "python", path: "/Users/xxx/python-app", ports: [5000], 
            scriptUrls: ["deploy": "https://raw.githubusercontent.com/zhangc536/ritual-ubuntn/refs/heads/main/deploy.sh"]),
    Project(id: "3", name: "Node.js API", type: "node", path: "/Users/xxx/node-app", ports: [3000], 
            scriptUrls: ["deploy": "https://raw.githubusercontent.com/zhangc536/ritual-ubuntn/refs/heads/main/deploy.sh"])
]

print("Testing batch deployment functionality...\n")

// 测试批量部署
MockProjectRunner.deployAll(projects: projects) { log in
    logger.addLog(log)
}

// 等待一段时间让异步操作完成
Thread.sleep(forTimeInterval: 10)

print("\nBatch deployment test completed.")