import Foundation
import Combine
import AppKit

public class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = UpdateManager()
    
    @Published public var isChecking = false
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var updateStatus: String? = nil
    @Published public var newVersionURL: URL? = nil
    @Published public var downloadURL: URL? = nil
    @Published public var newVersionString: String? = nil
    
    private let repoURL = "https://api.github.com/repos/thesadboy/PasteFlow/releases/latest"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    private override init() {
        super.init()
    }
    
    public func checkForUpdates() {
        guard !isChecking && !isDownloading else { return }
        
        DispatchQueue.main.async {
            self.isChecking = true
            self.updateStatus = "正在检查更新..."
            self.newVersionURL = nil
            self.downloadURL = nil
            self.newVersionString = nil
        }
        
        guard let url = URL(string: repoURL) else {
            self.setFailed(message: "检查失败：无效的 URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // 防止被 GitHub API 速率限制或缓存
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.setFailed(message: "网络错误: \(error.localizedDescription)")
                return
            }
            
            // 检查响应状态码，防止 API 请求限制导致的静默错误
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if httpResponse.statusCode == 403 {
                    self.setFailed(message: "请求频繁，请稍后再试 (GitHub API 限制)")
                } else {
                    self.setFailed(message: "检查更新失败 (HTTP \(httpResponse.statusCode))")
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLStr = json["html_url"] as? String else {
                self.setFailed(message: "获取更新信息失败")
                return
            }
            
            var dmgURLStr: String? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                       let downloadURL = asset["browser_download_url"] as? String {
                        dmgURLStr = downloadURL
                        break
                    }
                }
            }
            
            let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
            
            DispatchQueue.main.async {
                self.isChecking = false
                if self.compareVersions(latest: latestVersion, current: self.currentVersion) {
                    self.updateStatus = "发现新版本：v\(latestVersion)"
                    self.newVersionString = latestVersion
                    self.newVersionURL = URL(string: htmlURLStr)
                    if let dmg = dmgURLStr {
                        self.downloadURL = URL(string: dmg)
                    }
                } else {
                    self.updateStatus = "已是最新版本"
                }
            }
        }.resume()
    }
    
    public func downloadAndInstall() {
        guard let url = downloadURL else { return }
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.updateStatus = "正在连接下载..."
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async {
                self.downloadProgress = progress
                self.updateStatus = String(format: "正在下载更新包... %d%%", Int(progress * 100))
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        DispatchQueue.main.async {
            self.updateStatus = "下载完成，正在准备安装..."
        }
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("PasteFlowUpdate_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        
        let dmgURL = tempDir.appendingPathComponent("PasteFlow.dmg")
        do {
            try fileManager.moveItem(at: location, to: dmgURL)
        } catch {
            self.setFailed(message: "文件移动失败")
            return
        }
        
        let scriptPath = tempDir.appendingPathComponent("install.sh").path
        let scriptContent = """
        #!/bin/bash
        # 延迟1秒等待主程序退出
        sleep 1
        
        echo "Mounting DMG..."
        hdiutil attach "\(dmgURL.path)" -nobrowse -quiet -mountpoint /Volumes/PasteFlowUpdate
        
        if [ -d "/Volumes/PasteFlowUpdate/PasteFlow.app" ]; then
            echo "Copying to Applications..."
            cp -R /Volumes/PasteFlowUpdate/PasteFlow.app /Applications/
            # 清理下载隔离属性
            xattr -cr /Applications/PasteFlow.app 2>/dev/null || true
        fi
        
        echo "Unmounting DMG..."
        hdiutil detach /Volumes/PasteFlowUpdate -quiet -force 2>/dev/null || true
        
        echo "Relaunching app..."
        open /Applications/PasteFlow.app
        
        echo "Cleaning up..."
        rm -rf "\(tempDir.path)"
        """
        
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            var attributes = try fileManager.attributesOfItem(atPath: scriptPath)
            attributes[.posixPermissions] = NSNumber(value: 0o777)
            try fileManager.setAttributes(attributes, ofItemAtPath: scriptPath)
            
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath]
            try proc.run()
            
            DispatchQueue.main.async {
                NSApp.terminate(nil) // 退出当前应用以允许覆盖
            }
        } catch {
            self.setFailed(message: "安装脚本执行失败")
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            self.setFailed(message: "下载失败: \(error.localizedDescription)")
        }
    }
    
    private func setFailed(message: String) {
        DispatchQueue.main.async {
            self.isChecking = false
            self.isDownloading = false
            self.updateStatus = message
        }
    }
    
    // Returns true if latest > current
    private func compareVersions(latest: String, current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestParts.count, currentParts.count)
        
        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
