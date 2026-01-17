import Foundation

enum UpdateCheckResult {
    case noUpdate(current: String)
    case updateAvailable(current: String, remote: Version)
    case failure(String)
}

final class VersionManager {
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
    
    private static func makeMetadataURL(from urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else {
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

