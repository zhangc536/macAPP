import Foundation
import CryptoKit
import AppKit
import Darwin

enum UpdateCheckResult {
    case noUpdate(current: String)
    case updateAvailable(current: String, remote: Version)
    case failure(String)
}

final class VersionManager {
    private struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func currentAppVersion() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return value
        }
        return "0.0.0"
    }
    
    static func loadLocalVersion() -> Version? {
        guard let path = Bundle.main.path(forResource: "version", ofType: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Version.self, from: data)
        } catch {
            return nil
        }
    }
    
    static func checkForUpdate(completion: @escaping (UpdateCheckResult) -> Void) {
        let current = currentAppVersion()
        guard let local = loadLocalVersion() else {
            completion(.failure("本地版本信息缺失"))
            return
        }
        guard let metadataURL = makeMetadataURL(from: local.url) else {
            completion(.failure("更新元数据地址无效"))
            return
        }
        
        let request = URLRequest(url: metadataURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error.localizedDescription))
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure("未收到数据"))
                }
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let remote = try decoder.decode(Version.self, from: data)
                let compareResult = compareVersion(current, remote.version)
                DispatchQueue.main.async {
                    if compareResult < 0 {
                        completion(.updateAvailable(current: current, remote: remote))
                    } else {
                        completion(.noUpdate(current: current))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error.localizedDescription))
                }
            }
        }
        task.resume()
    }

    static func downloadAndInstall(remote: Version, progress: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanedURLString = normalizedURLString(remote.url)
        guard let dmgURL = URL(string: cleanedURLString) else {
            completion(.failure(InstallError(message: "下载地址无效")))
            return
        }

        let request = URLRequest(url: dmgURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        progress("正在下载更新…")

        let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = "下载失败：服务器返回状态码 \(httpResponse.statusCode)"
                DispatchQueue.main.async {
                    completion(.failure(InstallError(message: message)))
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    completion(.failure(InstallError(message: "下载失败：未生成临时文件")))
                }
                return
            }
            
            do {
                let downloadsDir = try ensureUpdateDownloadDirectory()
                let targetURL = downloadsDir.appendingPathComponent("update.dmg")
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: targetURL)
                } catch {
                    try FileManager.default.copyItem(at: tempURL, to: targetURL)
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        DispatchQueue.main.async {
                            progress("正在校验更新包…")
                        }
                        
                        if let expectedSize = remote.size {
                            let attrs = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? -1
                            if fileSize != expectedSize {
                                throw NSError(domain: "Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件大小不匹配"])
                            }
                        }
                        
                        if let expectedSHA256 = remote.sha256?.trimmingCharacters(in: shaTrimCharacters), !expectedSHA256.isEmpty {
                            let actual = try sha256Hex(of: targetURL)
                            if actual.lowercased() != expectedSHA256.lowercased() {
                                throw NSError(domain: "Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "SHA256 校验失败"])
                            }
                        }
                        
                        DispatchQueue.main.async {
                            progress("正在准备安装…")
                        }
                        
                        try mountAndStageInstall(dmgURL: targetURL)
                        
                        try? FileManager.default.removeItem(at: targetURL)
                        
                        DispatchQueue.main.async {
                            completion(.success(()))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                NSApplication.shared.terminate(nil)
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            let nsError = error as NSError
                            if nsError.domain == "Update" && (nsError.code == 10 || nsError.code == 11 || nsError.code == 12) {
                                NSWorkspace.shared.open(targetURL)
                            }
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
    private static func makeMetadataURL(from urlString: String) -> URL? {
        let cleaned = normalizedURLString(urlString)
        guard var components = URLComponents(string: cleaned) else {
            return nil
        }
        if let last = components.path.split(separator: ".").last, last == "dmg" {
            var segments = components.path.split(separator: "/").map(String.init)
            if let filename = segments.last {
                let base = filename.split(separator: ".").dropLast().joined(separator: ".")
                segments[segments.count - 1] = base + ".json"
                components.path = "/" + segments.joined(separator: "/")
            }
        }
        return components.url
    }

    private static func ensureUpdateDownloadDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "YourApp"
        let dir = base.appendingPathComponent(bundle).appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func mountAndStageInstall(dmgURL: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("YourAppUpdateMount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = runProcess(executable: "/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, dmgURL.path])
        guard attach.status == 0 else {
            throw NSError(domain: "Update", code: 10, userInfo: [NSLocalizedDescriptionKey: "挂载 DMG 失败"])
        }

        let appURL = try findAppBundle(in: mountPoint)
        let currentAppURL = Bundle.main.bundleURL
        let appName = currentAppURL.lastPathComponent
        let appDirectory = currentAppURL.deletingLastPathComponent()
        let destination = appDirectory.appendingPathComponent(appName)
        let staged = appDirectory.appendingPathComponent(appName + ".new")
        let backup = appDirectory.appendingPathComponent(appName + ".old")

        let pid = Int(getpid())
        let background = [
            "set -e",
            "pid=\(pid)",
            "dest=\(shQuote(destination.path))",
            "new=\(shQuote(staged.path))",
            "backup=\(shQuote(backup.path))",
            "while kill -0 \"$pid\" 2>/dev/null; do sleep 0.2; done",
            "rm -rf \"$backup\"",
            "if [ -d \"$dest\" ]; then mv \"$dest\" \"$backup\"; fi",
            "mv \"$new\" \"$dest\"",
            "/usr/bin/xattr -dr com.apple.quarantine \"$dest\" 2>/dev/null || true",
            "/usr/bin/open \"$dest\"",
        ].joined(separator: "; ")

        let command = [
            "set -e",
            "src=\(shQuote(appURL.path))",
            "mount=\(shQuote(mountPoint.path))",
            "staged=\(shQuote(staged.path))",
            "rm -rf \"$staged\"",
            "/usr/bin/ditto \"$src\" \"$staged\"",
            "/usr/bin/hdiutil detach \"$mount\" -force >/dev/null 2>&1 || true",
            "/usr/bin/nohup /bin/bash -c \(shQuote(background)) >/dev/null 2>&1 &",
        ].joined(separator: "; ")

        let semaphore = DispatchSemaphore(value: 0)
        var exitStatus: Int32 = 1
        var outputLog = ""
        AdminRunner.run(command: command, onOutput: { text in
            outputLog += text
        }, onExit: { status in
            exitStatus = status
            semaphore.signal()
        })
        semaphore.wait()

        if exitStatus != 0 {
            _ = runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            let trimmed = outputLog.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? "安装准备失败或取消授权" : "安装失败：\(trimmed)"
            throw NSError(domain: "Update", code: 11, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func findAppBundle(in mountPoint: URL) throws -> URL {
        let expectedName = Bundle.main.bundleURL.lastPathComponent
        let expectedURL = mountPoint.appendingPathComponent(expectedName)
        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return expectedURL
        }

        let enumerator = FileManager.default.enumerator(at: mountPoint, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app", url.lastPathComponent == expectedName {
                return url
            }
        }
        throw NSError(domain: "Update", code: 12, userInfo: [NSLocalizedDescriptionKey: "未在 DMG 中找到 \(expectedName)"])
    }

    private static func runProcess(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (1, "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func shQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let urlTrimCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`'\""))
    private static let shaTrimCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\""))

    private static func normalizedURLString(_ raw: String) -> String {
        raw.trimmingCharacters(in: urlTrimCharacters)
    }
    
    private static func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(lhsParts.count, rhsParts.count)
        for index in 0..<maxCount {
            let l = index < lhsParts.count ? lhsParts[index] : 0
            let r = index < rhsParts.count ? rhsParts[index] : 0
            if l < r {
                return -1
            } else if l > r {
                return 1
            }
        }
        return 0
    }
}
