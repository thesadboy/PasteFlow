import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public static var shared: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
    
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory app — no Dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Setup Menu Bar Item if enabled
        updateStatusBarVisibility()
        
        // Start Clipboard Monitoring
        ClipboardMonitor.shared.startMonitoring()
        
        // Register Global Carbon HotKey: Cmd + Shift + V
        HotkeyManager.shared.registerGlobalHotkey()
        
        // Register Apple Event handler for reopen (e.g. double clicking app icon while already running)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopenAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pauseStatusChanged),
            name: NSNotification.Name("PasteFlowPauseStatusChanged"),
            object: nil
        )
        
        print("[PasteFlow] App launched successfully. Press Cmd+Shift+V to toggle.")
    }
    
    @objc private func pauseStatusChanged() {
        DispatchQueue.main.async { [weak self] in
            if AppState.shared.isMonitoringPaused {
                self?.statusItem?.button?.toolTip = "PasteFlow (\(AppState.shared.pauseStatusDescription))"
            } else {
                self?.statusItem?.button?.toolTip = "PasteFlow"
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        HotkeyManager.shared.unregisterGlobalHotkeys()
    }
    
    // MARK: - Reopen Handlers (Double clicking app in Finder/Launchpad/Spotlight while running)
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async {
            AppState.shared.showOverlay()
        }
        return true
    }
    
    @objc private func handleReopenAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        DispatchQueue.main.async {
            AppState.shared.showOverlay()
        }
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.host == "settings" || url.path.contains("settings") {
                SettingsWindowManager.shared.showSettingsWindow()
            } else if url.host == "toggle" || url.path.contains("toggle") {
                AppState.shared.toggleOverlay()
            } else if url.host == "show" || url.path.contains("show") {
                AppState.shared.showOverlay()
            }
        }
    }
    
    // MARK: - Status Bar Setup
    
    public func updateStatusBarVisibility() {
        let showIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if showIcon {
            if statusItem == nil {
                setupStatusBar()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
    
    private func setupStatusBar() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteFlow") {
                let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
                button.image = image.withSymbolConfiguration(config)
            } else if let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "PasteFlow") {
                button.image = image
            } else {
                button.title = "📋"
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        buildMenu()
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Right Click shows standard menu
            updateRecentItemsMenu()
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Left click toggles the iconic bottom shelf!
            AppState.shared.toggleOverlay()
        }
    }
    
    private func buildMenu() {
        statusMenu = NSMenu()
        statusMenu.delegate = self
        updateRecentItemsMenu()
    }
    
    private func updateRecentItemsMenu() {
        statusMenu.removeAllItems()
        
        // Toggle item
        let toggleItem = NSMenuItem(
            title: "显示 / 隐藏 PasteFlow (\(HotkeyManager.shared.currentDisplayString))",
            action: #selector(togglePaste),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu.addItem(toggleItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Recent 5 items section
        let recentHeader = NSMenuItem(title: "最近剪贴板：", action: nil, keyEquivalent: "")
        recentHeader.isEnabled = false
        statusMenu.addItem(recentHeader)
        
        let recentItems = Array(AppState.shared.items.prefix(5))
        if recentItems.isEmpty {
            let emptyItem = NSMenuItem(title: "  (暂无历史记录)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            statusMenu.addItem(emptyItem)
        } else {
            for (idx, item) in recentItems.enumerated() {
                var title = item.plainText.replacingOccurrences(of: "\n", with: " ")
                if title.count > 30 {
                    title = String(title.prefix(30)) + "..."
                }
                let menuItem = NSMenuItem(
                    title: "  \(idx + 1). \(title)",
                    action: #selector(recentItemClicked(_:)),
                    keyEquivalent: ""
                )
                menuItem.representedObject = item
                menuItem.target = self
                statusMenu.addItem(menuItem)
            }
        }
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Settings item
        let settingsItem = NSMenuItem(
            title: "偏好设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        statusMenu.addItem(settingsItem)
        
        // Check for updates item
        let updateItem = NSMenuItem(
            title: "检查更新...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        statusMenu.addItem(updateItem)
        
        // Pause / Resume item with durations
        if AppState.shared.isMonitoringPaused {
            let resumeItem = NSMenuItem(
                title: "启用 PasteFlow (\(AppState.shared.pauseStatusDescription))",
                action: #selector(resumeMonitoringAction),
                keyEquivalent: ""
            )
            resumeItem.target = self
            statusMenu.addItem(resumeItem)
        } else {
            let pauseMenu = NSMenu()
            
            let item10 = NSMenuItem(title: "暂停 10 分钟", action: #selector(pause10MinutesAction), keyEquivalent: "")
            item10.target = self
            pauseMenu.addItem(item10)
            
            let item15 = NSMenuItem(title: "暂停 15 分钟", action: #selector(pause15MinutesAction), keyEquivalent: "")
            item15.target = self
            pauseMenu.addItem(item15)
            
            let item30 = NSMenuItem(title: "暂停 30 分钟", action: #selector(pause30MinutesAction), keyEquivalent: "")
            item30.target = self
            pauseMenu.addItem(item30)
            
            let item60 = NSMenuItem(title: "暂停 1 小时", action: #selector(pause1HourAction), keyEquivalent: "")
            item60.target = self
            pauseMenu.addItem(item60)
            
            pauseMenu.addItem(NSMenuItem.separator())
            
            let itemForever = NSMenuItem(title: "永久暂停", action: #selector(pauseIndefinitelyAction), keyEquivalent: "")
            itemForever.target = self
            pauseMenu.addItem(itemForever)
            
            let pauseItem = NSMenuItem(title: "暂停 PasteFlow", action: nil, keyEquivalent: "")
            pauseItem.submenu = pauseMenu
            statusMenu.addItem(pauseItem)
        }
        
        // Clear history item
        let clearItem = NSMenuItem(
            title: "清空剪贴板历史记录",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        statusMenu.addItem(clearItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(
            title: "退出 PasteFlow",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc private func togglePaste() {
        AppState.shared.toggleOverlay()
    }
    
    @objc private func recentItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipItem else { return }
        PasteManager.shared.paste(item: item)
    }
    
    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettingsWindow()
    }
    
    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }
    
    @objc private func resumeMonitoringAction() {
        AppState.shared.resumeMonitoring()
    }
    
    @objc private func pause10MinutesAction() {
        AppState.shared.pauseMonitoring(for: .tenMinutes)
    }
    
    @objc private func pause15MinutesAction() {
        AppState.shared.pauseMonitoring(for: .fifteenMinutes)
    }
    
    @objc private func pause30MinutesAction() {
        AppState.shared.pauseMonitoring(for: .thirtyMinutes)
    }
    
    @objc private func pause1HourAction() {
        AppState.shared.pauseMonitoring(for: .oneHour)
    }
    
    @objc private func pauseIndefinitelyAction() {
        AppState.shared.pauseMonitoring(for: .indefinitely)
    }
    
    @objc private func clearHistory() {
        AppState.shared.clearHistory()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
