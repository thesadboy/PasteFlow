import AppKit
import ApplicationServices
import Foundation

public final class PasteManager {
    public static let shared = PasteManager()
    
    public var isSelfCopying: Bool = false
    public private(set) var previousApp: NSRunningApplication?
    
    private init() {
        // Monitor frontmost app changes to keep previousApp updated
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func workspaceDidActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if isValidTargetApp(app) {
            previousApp = app
        }
    }
    
    /// Records the frontmost application before opening PasteFlow overlay
    public func recordPreviousApp() {
        if let front = NSWorkspace.shared.frontmostApplication, isValidTargetApp(front) {
            previousApp = front
            print("[PasteManager] Recorded previousApp: \(front.localizedName ?? "") (\(front.bundleIdentifier ?? ""))")
        }
    }
    
    /// Checks if an application can validly receive pasted content
    private func isValidTargetApp(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else { return false }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        
        let ignoredBundleIds: Set<String> = [
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.Dock"
        ]
        if let bid = app.bundleIdentifier, ignoredBundleIds.contains(bid) {
            return false
        }
        return app.activationPolicy == .regular
    }
    
    /// Resolves the most accurate application to paste into
    public var effectiveTargetApp: NSRunningApplication? {
        if let app = previousApp, isValidTargetApp(app) {
            return app
        }
        if let front = NSWorkspace.shared.frontmostApplication, isValidTargetApp(front) {
            return front
        }
        return NSWorkspace.shared.runningApplications.first { isValidTargetApp($0) && $0.isActive }
            ?? NSWorkspace.shared.runningApplications.first { isValidTargetApp($0) }
    }
    
    // Check if Accessibility permissions are granted (live check)
    public func isAccessibilityGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    public func openSystemAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "为了实现自动粘贴功能，PasteFlow 需要「辅助功能」权限。\n\n💡 提示：如果系统设置中已经勾选了 PasteFlow 但仍然提示此信息，这是 macOS 系统的权限缓存 Bug。请在设置中选中 PasteFlow，点击下方的“-”号将其删除，然后重新添加并勾选即可。\n\n目前内容已复制到剪贴板，您可以手动使用 Cmd+V 粘贴。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往设置")
        alert.addButton(withTitle: "取消")
        
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            self.requestAccessibilityPermission()
        }
    }
    
    private var isPasting: Bool = false
    
    // Core Paste Action
    public func paste(item: ClipItem, plainTextOnly: Bool = false) {
        guard !isPasting else { return }
        isPasting = true
        
        let isAlwaysPlainText = UserDefaults.standard.bool(forKey: "pastePlainTextDefault")
        let shouldPlainText = plainTextOnly || isAlwaysPlainText
        let pasteTarget = UserDefaults.standard.string(forKey: "pasteTarget") ?? "activeApp"
        
        if pasteTarget == "clipboard" {
            // Copy to clipboard mode
            copyToClipboard(item: item, plainTextOnly: shouldPlainText)
            DispatchQueue.main.async {
                AppState.shared.hideOverlay()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isPasting = false
            }
            return
        }
        
        // Active App mode: write to pasteboard and prepare target app
        isSelfCopying = true
        copyItemToPasteboard(item: item, plainTextOnly: shouldPlainText)
        SoundManager.shared.playPasteSound()
        AppState.shared.promoteItem(item)
        
        let targetApp = effectiveTargetApp
        print("[PasteManager] Pasting item to target app: \(targetApp?.localizedName ?? "none") (\(targetApp?.bundleIdentifier ?? "none"))")
        
        // Hide overlay IMMEDIATELY so the target window regains focus without animation delays
        DispatchQueue.main.async {
            AppState.shared.hideOverlay(immediately: true)
        }
        
        // Activate target app and execute simulated Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            
            if let target = targetApp {
                target.activate(options: .activateIgnoringOtherApps)
            }
            
            // Allow 120ms for target app window & text field to become first responder
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if self.isAccessibilityGranted() {
                    self.simulateCmdV()
                } else {
                    print("[PasteManager] Accessibility permission not granted for simulated Cmd+V. Content copied to clipboard.")
                    self.showAccessibilityPrompt()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isSelfCopying = false
                    self.isPasting = false
                }
            }
        }
    }
    
    // Copy only without auto-pasting
    public func copyToClipboard(item: ClipItem, plainTextOnly: Bool = false) {
        isSelfCopying = true
        copyItemToPasteboard(item: item, plainTextOnly: plainTextOnly)
        SoundManager.shared.playCopySound()
        AppState.shared.promoteItem(item)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isSelfCopying = false
        }
    }
    
    private func copyItemToPasteboard(item: ClipItem, plainTextOnly: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if plainTextOnly {
            pasteboard.setString(item.plainText, forType: .string)
            return
        }
        
        switch item.type {
        case .image:
            if let fileName = item.imageFileName,
               let image = StorageManager.shared.loadImage(fileName: fileName) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(item.plainText, forType: .string)
            }
            
        case .file:
            if let paths = item.filePaths, !paths.isEmpty {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
                pasteboard.setPropertyList(paths, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
            } else {
                pasteboard.setString(item.plainText, forType: .string)
            }
            
        case .text, .code, .link, .color:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.plainText, forType: .string)
            
            var rtfData = item.richTextData
            var htmlData = item.htmlData
            
            // Safety check for legacy items where HTML was saved into richTextData
            if let data = rtfData {
                let isRTF = data.prefix(5).elementsEqual([0x7B, 0x5C, 0x72, 0x74, 0x66])
                if !isRTF {
                    if htmlData == nil {
                        htmlData = data
                    }
                    rtfData = nil
                }
            }
            
            // Synthesize RTF from HTML if missing (ensures Office / Pages compatibility)
            if rtfData == nil, let html = htmlData {
                if let attr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                    rtfData = try? attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                }
            }
            
            // Synthesize HTML from RTF if missing (ensures WPS / Browser / Electron compatibility)
            if htmlData == nil, let rtf = rtfData {
                if let attr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                    htmlData = try? attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
                }
            }
            
            if let rtf = rtfData {
                pbItem.setData(rtf, forType: .rtf)
            }
            if let html = htmlData {
                pbItem.setData(html, forType: .html)
            }
            
            pasteboard.writeObjects([pbItem])
        }
    }
    
    private func simulateCmdV() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key for 'v'
        
        // Use hidSystemState so physical keys (like Shift/Option held during shortcuts)
        // are NOT merged into the synthesized paste event
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[PasteManager] Failed to create CGEventSource")
            return
        }
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("[PasteManager] Failed to create CGEvent for Cmd+V")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post ONLY to cghidEventTap. WindowServer routes it once to the focused app.
        // Posting to both cghidEventTap and cgSessionEventTap causes duplicate paste events!
        keyDown.post(tap: .cghidEventTap)
        
        // Crucial 20ms delay between KeyDown and KeyUp so the receiving app's event loop
        // has time to register the press and dispatch the paste action before key release
        usleep(20_000) // 20ms
        
        keyUp.post(tap: .cghidEventTap)
        
        print("[PasteManager] Successfully dispatched single simulated Cmd+V")
    }
}
