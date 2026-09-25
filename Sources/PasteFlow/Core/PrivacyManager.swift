import AppKit
import Foundation

public struct IgnoredApp: Identifiable, Codable, Equatable, Hashable {
    public var id: String { bundleId }
    public var name: String
    public var bundleId: String
    public var isCustom: Bool
    
    public init(name: String, bundleId: String, isCustom: Bool = false) {
        self.name = name
        self.bundleId = bundleId
        self.isCustom = isCustom
    }
}

public final class PrivacyManager: ObservableObject {
    public static let shared = PrivacyManager()
    
    private let userDefaultsKey = "customIgnoredAppsList"
    
    public static let defaultApps: [IgnoredApp] = [
        IgnoredApp(name: "1Password", bundleId: "com.agilebits.onepassword", isCustom: false),
        IgnoredApp(name: "1Password 8", bundleId: "com.1password.1password", isCustom: false),
        IgnoredApp(name: "Bitwarden", bundleId: "com.bitwarden.desktop", isCustom: false),
        IgnoredApp(name: "钥匙串访问", bundleId: "com.apple.keychainaccess", isCustom: false),
        IgnoredApp(name: "Apple 密码与安全性", bundleId: "com.apple.Passwords", isCustom: false),
        IgnoredApp(name: "KeePassXC", bundleId: "org.keepassxc.keepassxc", isCustom: false)
    ]
    
    @Published public var customApps: [IgnoredApp] = []
    
    private init() {
        loadCustomApps()
    }
    
    public var allIgnoredApps: [IgnoredApp] {
        PrivacyManager.defaultApps + customApps
    }
    
    public func isIgnored(bundleId: String) -> Bool {
        guard !bundleId.isEmpty else { return false }
        return allIgnoredApps.contains { $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame }
    }
    
    public func addCustomApp(name: String, bundleId: String) {
        let trimmedId = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        
        if isIgnored(bundleId: trimmedId) {
            return
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = IgnoredApp(name: trimmedName.isEmpty ? trimmedId : trimmedName, bundleId: trimmedId, isCustom: true)
        customApps.append(app)
        saveCustomApps()
    }
    
    public func removeCustomApp(bundleId: String) {
        customApps.removeAll { $0.bundleId == bundleId }
        saveCustomApps()
    }
    
    public func selectAppFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "选择要忽略记录的应用程序"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        // Allowed content type for macOS applications
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.application]
        } else {
            panel.allowedFileTypes = ["app"]
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url) {
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let bundleId = bundle.bundleIdentifier ?? ""
                if !bundleId.isEmpty {
                    addCustomApp(name: name, bundleId: bundleId)
                }
            }
        }
    }
    
    public func getRunningApplications() -> [(name: String, bundleId: String, icon: NSImage?)] {
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let bid = app.bundleIdentifier, !bid.isEmpty else { return nil }
                let name = app.localizedName ?? bid
                return (name: name, bundleId: bid, icon: app.icon)
            }
            .filter { !isIgnored(bundleId: $0.bundleId) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func loadCustomApps() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let list = try? JSONDecoder().decode([IgnoredApp].self, from: data) {
            self.customApps = list
        }
    }
    
    private func saveCustomApps() {
        if let data = try? JSONEncoder().encode(customApps) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
