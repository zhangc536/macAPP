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

    private struct RemoteUpdateInfo: Codable {
        struct MacInfo: Codable {
            let url: String
            let sha256: String?
        }

        let latest_version: String
        let release_notes: String?
        let mac: MacInfo
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
        let metadataURLString = normalizedURLString(local.url)
        guard let metadataURL = URL(string: metadataURLString) else {
            completion(.failure("更新配置地址无效"))
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
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    completion(.failure("服务器返回状态码 \(httpResponse.statusCode)"))
                }
                return
            }
            do {
                let decoder = JSONDecoder()
                let info = try decoder.decode(RemoteUpdateInfo.self, from: data)
                let compareResult = compareVersion(current, info.latest_version)
                DispatchQueue.main.async {
                    if compareResult < 0 {
                        let remote = Version(
                            version: info.latest_version,
                            url: info.mac.url,
                            sha256: info.mac.sha256,
                            size: nil,
                            releaseNotes: info.release_notes,
                            releasedAt: nil
                        )
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
        guard let zipURL = URL(string: cleanedURLString) else {
            completion(.failure(InstallError(message: "下载地址无效")))
            return
        }

        let request = URLRequest(url: zipURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
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
                let targetURL = downloadsDir.appendingPathComponent("update.zip")
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
                        
                        if let expectedSHA256 = remote.sha256?.trimmingCharacters(in: shaTrimCharacters), !expectedSHA256.isEmpty {
                            let actual = try sha256Hex(of: targetURL)
                            if actual.lowercased() != expectedSHA256.lowercased() {
                                throw NSError(domain: "Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "SHA256 校验失败"])
                            }
                        }
                        
                        DispatchQueue.main.async {
                            progress("正在启动更新程序…")
                        }

                        try launchUpdater(with: targetURL)

                        let appURL = Bundle.main.bundleURL
                        let pid = getpid()
                        DispatchQueue.main.async {
                            progress("安装完成，正在重启…")
                            DispatchQueue.global(qos: .background).async {
                                let script = """
                                sleep 2;
                                kill \(pid);
                                sleep 1;
                                open \(shQuote(appURL.path));
                                """
                                let process = Process()
                                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                                process.arguments = ["-c", script]
                                try? process.run()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                completion(.success(()))
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
    
    private static func ensureUpdateDownloadDirectory() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacApp"
        let dir = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(appName)
            .appendingPathComponent("update", isDirectory: true)
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

    private static func launchUpdater(with zipURL: URL) throws {
        let bundleURL = Bundle.main.bundleURL
        let updaterURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("Updater")

        if !FileManager.default.isExecutableFile(atPath: updaterURL.path) {
            throw InstallError(message: "未找到更新程序 Updater")
        }

        let process = Process()
        process.executableURL = updaterURL
        process.arguments = [zipURL.path]
        try process.run()
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
