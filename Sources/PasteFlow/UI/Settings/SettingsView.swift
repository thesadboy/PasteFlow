import AppKit
import Carbon
import ServiceManagement
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case shortcuts = "快捷键"
    case pinboards = "分组"
    case privacy = "隐私"
    case accessibility = "权限"
    case about = "关于"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "command"
        case .pinboards: return "folder.fill"
        case .privacy: return "hand.raised.fill"
        case .accessibility: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }
}

public final class SettingsViewModel: ObservableObject {
    @Published public var selectedTab: SettingsTab = .general
    @Published public var isAccessibilityGranted: Bool = PasteManager.shared.isAccessibilityGranted()
    @Published public var recordingShortcutId: String? = nil
    @Published public var showingResetAlert: Bool = false
    @Published public var showingClearHistoryAlert: Bool = false
    
    // New pinboard state
    @Published public var newPinboardName: String = ""
    @Published public var selectedColorHex: String = "#3B82F6"
    
    // Delete pinboard confirmation state
    @Published public var pinboardToDelete: Pinboard? = nil
    @Published public var showingDeletePinboardAlert: Bool = false
    
    public func confirmDeletePinboard(_ pinboard: Pinboard) {
        pinboardToDelete = pinboard
        showingDeletePinboardAlert = true
    }
    
    // Edit pinboard state
    @Published public var editingPinboardId: UUID? = nil
    @Published public var editPinboardName: String = ""
    @Published public var editPinboardColorHex: String = "#3B82F6"
    
    public func startEditingPinboard(_ pinboard: Pinboard) {
        editingPinboardId = pinboard.id
        editPinboardName = pinboard.name
        editPinboardColorHex = pinboard.colorHex
    }
    
    public func cancelEditingPinboard() {
        editingPinboardId = nil
        editPinboardName = ""
    }
    
    public func saveEditingPinboard(appState: AppState) {
        guard let id = editingPinboardId else { return }
        let trimmed = editPinboardName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = appState.pinboards.first(where: { $0.id == id }) {
            var updated = existing
            updated.name = trimmed
            updated.colorHex = editPinboardColorHex
            appState.updatePinboard(updated)
        }
        editingPinboardId = nil
    }
    
    // Privacy custom app state
    @Published public var manualBundleId: String = ""
    
    // About tab update check state
    @Published public var checkingForUpdates: Bool = false
    @Published public var updateStatusText: String? = nil
    
    // Storage statistics state
    @Published public var storageSizeString: String = ""
    
    private var eventMonitor: Any?
    
    public init() {}
    
    public func refreshAccessibility() {
        let granted = PasteManager.shared.isAccessibilityGranted()
        DispatchQueue.main.async {
            self.isAccessibilityGranted = granted
        }
    }
    
    public func refreshStorageStats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let formatted = StorageManager.shared.formattedStorageSize()
            DispatchQueue.main.async {
                self?.storageSizeString = formatted
            }
        }
    }
    
    public func startRecording(for shortcutId: String) {
        stopRecording()
        recordingShortcutId = shortcutId
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // ESC key cancels recording
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isGlobal = (shortcutId == "activatePaste" || shortcutId == "activatePasteStack")
            
            // Global shortcuts require at least one modifier key (Cmd, Shift, Opt, or Ctrl)
            if isGlobal && flags.isEmpty {
                return event
            }
            
            let carbonMods = HotkeyManager.carbonModifiers(from: flags)
            let displayStr = HotkeyManager.displayString(keyCode: event.keyCode, flags: flags)
            
            HotkeyManager.shared.updateShortcut(
                id: shortcutId,
                keyCode: UInt32(event.keyCode),
                modifiers: carbonMods,
                displayString: displayStr
            )
            self.stopRecording()
            return nil
        }
    }
    
    public func stopRecording() {
        recordingShortcutId = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    deinit {
        stopRecording()
    }
}

public final class PinboardSettingsRowModel: ObservableObject {
    @Published public var isDropTargeted: Bool = false
    public init() {}
}

public struct PinboardSettingsRowDropDelegate: DropDelegate {
    let pinboard: Pinboard
    let appState: AppState
    @ObservedObject var rowModel: PinboardSettingsRowModel
    
    public func dropEntered(info: DropInfo) {
        rowModel.isDropTargeted = true
    }
    
    public func dropExited(info: DropInfo) {
        rowModel.isDropTargeted = false
    }
    
    public func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    public func performDrop(info: DropInfo) -> Bool {
        rowModel.isDropTargeted = false
        guard let provider = info.itemProviders(for: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"]).first else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { stringObj, _ in
            guard let str = stringObj as? String else { return }
            DispatchQueue.main.async {
                let prefix: String?
                if str.hasPrefix("pasteflow-pinboard-settings:") {
                    prefix = "pasteflow-pinboard-settings:"
                } else if str.hasPrefix("pasteflow-pinboard:") {
                    prefix = "pasteflow-pinboard:"
                } else {
                    prefix = nil
                }
                
                if let prefix = prefix {
                    let idStr = String(str.dropFirst(prefix.count))
                    if let sourceId = UUID(uuidString: idStr) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.movePinboard(id: sourceId, targetId: pinboard.id)
                            SoundManager.shared.playCopySound()
                        }
                    }
                }
            }
        }
        return true
    }
}

public struct PinboardSettingsRowView: View {
    public let pinboard: Pinboard
    public let index: Int
    public let totalCount: Int
    @ObservedObject public var appState: AppState
    @ObservedObject public var vm: SettingsViewModel
    
    @StateObject private var rowModel = PinboardSettingsRowModel()
    
    public init(
        pinboard: Pinboard,
        index: Int,
        totalCount: Int,
        appState: AppState,
        vm: SettingsViewModel
    ) {
        self.pinboard = pinboard
        self.index = index
        self.totalCount = totalCount
        self.appState = appState
        self.vm = vm
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Drag handle icon
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 14)
                .help("按住并拖动以重新排序")
            
            Circle()
                .fill(pinboard.color)
                .frame(width: 12, height: 12)
            
            Text(pinboard.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            let count = appState.items.filter { $0.pinboardId == pinboard.id }.count
            Text("\(count) 项")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.movePinboardLeft(pinboard)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(index > 0 ? .secondary : .secondary.opacity(0.3))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("上移分组")
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.movePinboardRight(pinboard)
                }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11))
                    .foregroundColor(index < totalCount - 1 ? .secondary : .secondary.opacity(0.3))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index >= totalCount - 1)
            .help("下移分组")
            
            Button {
                vm.startEditingPinboard(pinboard)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("编辑分组")
            
            Button {
                vm.confirmDeletePinboard(pinboard)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("删除分组")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowModel.isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(rowModel.isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: rowModel.isDropTargeted)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: "pasteflow-pinboard-settings:\(pinboard.id.uuidString)" as NSString)
        }
        .onDrop(of: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"], delegate: PinboardSettingsRowDropDelegate(pinboard: pinboard, appState: appState, rowModel: rowModel))
        .help("按住左侧图标或整行可拖动重新排序")
    }
}

public struct SettingsView: View {
    @AppStorage("playSoundEffects") private var playSoundEffects: Bool = true
    @AppStorage("pastePlainTextDefault") private var pastePlainTextDefault: Bool = false
    @AppStorage("pasteTarget") private var pasteTarget: String = "activeApp"
    @AppStorage("runInBackground") private var runInBackground: Bool = true
    @AppStorage("historyRetentionIndex") private var historyRetentionIndex: Double = 3.0
    @AppStorage("historyCapacityLimit") private var historyCapacityLimit: Int = 500
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @ObservedObject private var updater = UpdateManager.shared
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Modern macOS segmented tab navigation bar
            HStack(spacing: 5) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            vm.selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: vm.selectedTab == tab ? .semibold : .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(vm.selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(vm.selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.4)
            
            // Tab Content Area - Scrollable with 100% full width and left alignment
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    switch vm.selectedTab {
                    case .general:
                        generalView
                    case .shortcuts:
                        shortcutsView
                    case .pinboards:
                        pinboardsView
                    case .privacy:
                        privacyView
                    case .accessibility:
                        accessibilityView
                    case .about:
                        aboutView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            vm.refreshAccessibility()
            vm.refreshStorageStats()
        }
        .onChange(of: appState.items.count) { _ in
            vm.refreshStorageStats()
        }
        .onChange(of: vm.selectedTab) { newTab in
            if newTab == .accessibility || newTab == .general {
                vm.refreshAccessibility()
            }
            if newTab == .general {
                vm.refreshStorageStats()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshAccessibility()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if vm.selectedTab == .accessibility || vm.selectedTab == .general {
                vm.refreshAccessibility()
            }
        }
    }
    
    // MARK: - General Tab (100% 对标 Paste 官方设计，完整左对齐与右侧控制项)
    private var generalView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section 1: 应用程序行为
            settingsCard(title: "应用程序行为") {
                settingToggleRow(
                    title: "登录时打开",
                    subtitle: "在开机登录系统时自动启动 PasteFlow",
                    isOn: $launchAtLogin
                ) { val in
                    setLaunchAtLogin(enabled: val)
                }
                
                cardDivider()
                
                settingToggleRow(
                    title: "在菜单栏显示图标",
                    subtitle: "关闭后可通过快捷键 ⌘⇧V 随时呼出主界面与设置",
                    isOn: $showMenuBarIcon
                ) { _ in
                    AppDelegate.shared?.updateStatusBarVisibility()
                }
                
                cardDivider()
                
                settingToggleRow(
                    title: "后台运行",
                    subtitle: "关闭所有界面后仍在菜单栏后台持续运行",
                    isOn: $runInBackground
                )
                
                cardDivider()
                
                settingToggleRow(
                    title: "音效",
                    subtitle: "记录剪贴板与模拟粘贴时播放反馈提示音",
                    isOn: $playSoundEffects
                )
            }
            
            // Section 2: 粘贴项目
            settingsCard(title: "粘贴选项") {
                // Option 1: 到当前活动应用
                Button {
                    pasteTarget = "activeApp"
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pasteTarget == "activeApp" ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundColor(pasteTarget == "activeApp" ? .accentColor : .secondary)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("到当前活动应用")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("将选定的项目直接自动粘贴到您当前正在使用的应用程序中。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            if !vm.isAccessibilityGranted {
                                Button {
                                    PasteManager.shared.requestAccessibilityPermission()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        vm.refreshAccessibility()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 11))
                                        Text("需要辅助功能权限以支持直接粘贴，点击授权")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                cardDivider()
                
                // Option 2: 到剪贴板
                Button {
                    pasteTarget = "clipboard"
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pasteTarget == "clipboard" ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundColor(pasteTarget == "clipboard" ? .accentColor : .secondary)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("到剪贴板")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("仅将选定的项目复制到系统剪贴板，稍后由您手动按 ⌘V 进行粘贴。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                cardDivider()
                
                settingToggleRow(
                    title: "始终以纯文本粘贴",
                    subtitle: "粘贴时移除所有富文本排版、字体格式与颜色",
                    isOn: $pastePlainTextDefault
                )
            }
            
            // Section 3: 历史记录与存储统计
            settingsCard(title: "历史记录与存储") {
                // 存储统计与记录数量指标卡
                HStack(spacing: 0) {
                    // 指标 1: 历史记录总数
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("历史记录总数")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(appState.items.count)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("条")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                        .frame(height: 32)
                        .padding(.horizontal, 12)
                    
                    // 指标 2: 空间占用
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "internaldrive")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("存储空间占用")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(vm.storageSizeString.isEmpty ? "计算中..." : vm.storageSizeString)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                
                cardDivider()
                
                // 记录细分与访达跳转
                HStack {
                    let pinnedCount = appState.items.filter { $0.isPinned || $0.pinboardId != nil }.count
                    let regularCount = max(0, appState.items.count - pinnedCount)
                    Text("普通历史 \(regularCount) 条 · 分组及固定 \(pinnedCount) 条")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button {
                        StorageManager.shared.openStorageFolderInFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Text("在访达中显示数据")
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                cardDivider()
                
                // 保留历史时间
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("保留历史时间")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(retentionTitle(for: Int(historyRetentionIndex)))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(5)
                    }
                    
                    Slider(value: $historyRetentionIndex, in: 0...4, step: 1)
                        .onChange(of: historyRetentionIndex) { _ in
                            appState.pruneExpiredHistory()
                            vm.refreshStorageStats()
                        }
                    
                    HStack {
                        Text("1 天").frame(maxWidth: .infinity, alignment: .leading)
                        Text("1 周").frame(maxWidth: .infinity, alignment: .center)
                        Text("1 个月").frame(maxWidth: .infinity, alignment: .center)
                        Text("1 年").frame(maxWidth: .infinity, alignment: .center)
                        Text("永久").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    
                    Text("💡 提示：放入分组中的项目和已固定的卡片将永久保留，不受保留时间限制。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                cardDivider()
                
                // 最大历史容量
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("最大历史容量")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                        Text("超出容量的较早普通记录将自动淘汰，已固定与分组内容永久受保护")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $historyCapacityLimit) {
                        Text("100 条").tag(100)
                        Text("300 条").tag(300)
                        Text("500 条 (默认)").tag(500)
                        Text("1000 条").tag(1000)
                        Text("2000 条").tag(2000)
                        Text("不限制").tag(-1)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .onChange(of: historyCapacityLimit) { _ in
                        appState.enforceCapacityLimit()
                        vm.refreshStorageStats()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                cardDivider()
                
                // 清空历史
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清空历史记录")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                        Text("已固定卡片和分组中的内容会被安全保留")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        vm.showingClearHistoryAlert = true
                    } label: {
                        Text("清空历史...")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .alert("您确定要清空剪贴板历史记录吗？", isPresented: $vm.showingClearHistoryAlert) {
                        Button("取消", role: .cancel) {}
                        Button("清空", role: .destructive) {
                            appState.clearHistory()
                            vm.refreshStorageStats()
                        }
                    } message: {
                        Text("已固定的项目和分组中的内容不会被删除。此操作无法撤销。")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private func retentionTitle(for index: Int) -> String {
        switch index {
        case 0: return "1 天"
        case 1: return "1 周"
        case 2: return "1 个月"
        case 3: return "1 年"
        case 4: return "永久"
        default: return "1 年"
        }
    }
    
    // MARK: - Shortcuts Tab (完全 1:1 对标 Paste 软件的布局与交互)
    private var shortcutsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Group 1: 启动与界面
            settingsCard(title: "全局快捷键") {
                shortcutRow(
                    title: "显示 / 隐藏 PasteFlow",
                    subtitle: "在屏幕底部呼出或收起剪贴板面板",
                    shortcut: hotkeyManager.activatePasteShortcut
                )
                
                cardDivider()
                
                shortcutRow(
                    title: "激活 Paste Stack 连续粘贴",
                    subtitle: "按复制顺序连续粘贴多个项目",
                    shortcut: hotkeyManager.activatePasteStackShortcut
                )
            }
            
            // Group 2: 分组切换
            settingsCard(title: "分组导航") {
                shortcutRow(
                    title: "显示下一个分组",
                    subtitle: "在打开面板时切换到右侧相邻分类",
                    shortcut: hotkeyManager.nextPinboardShortcut
                )
                
                cardDivider()
                
                shortcutRow(
                    title: "显示上一个分组",
                    subtitle: "在打开面板时切换到左侧相邻分类",
                    shortcut: hotkeyManager.previousPinboardShortcut
                )
            }
            
            // Group 3: 修饰键选项
            settingsCard(title: "修饰键选项") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("快速粘贴")
                            .font(.system(size: 13, weight: .regular))
                        Text("按住修饰键并按数字键 1...9 快速粘贴前 9 个项目")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $hotkeyManager.quickPasteModifier) {
                        Text("⌘ Command").tag(ModifierOption.command)
                        Text("⌥ Option").tag(ModifierOption.option)
                        Text("⌃ Control").tag(ModifierOption.control)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    
                    Text("+ 1...9")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                
                cardDivider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("纯文本模式")
                            .font(.system(size: 13, weight: .regular))
                        Text("按住修饰键粘贴时临时过滤格式为纯文本")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $hotkeyManager.plainTextModifier) {
                        Text("⇧ Shift").tag(ModifierOption.shift)
                        Text("⌥ Option").tag(ModifierOption.option)
                        Text("⌃ Control").tag(ModifierOption.control)
                        Text("⌘ Command").tag(ModifierOption.command)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            
            // 底部操作栏
            HStack {
                if vm.recordingShortcutId != nil {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("请按下新的快捷键组合（按 Esc 取消录制）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Button("将快捷方式重置为默认") {
                    vm.showingResetAlert = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .alert("您确定要将所有快捷方式重置为默认值吗？", isPresented: $vm.showingResetAlert) {
                    Button("取消", role: .cancel) {}
                    Button("重置", role: .destructive) {
                        hotkeyManager.resetToDefault()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Pinboards Tab (管理分组分类，支持创建、颜色选择与删除)
    private var pinboardsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Existing Pinboards List
            settingsCard(title: "现有的分组分类") {
                if appState.pinboards.isEmpty {
                    Text("暂无分组，您可以在下方添加新的分类。")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(appState.pinboards.enumerated()), id: \.element.id) { index, pinboard in
                        if index > 0 {
                            cardDivider()
                        }
                        
                        if vm.editingPinboardId == pinboard.id {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    TextField("分组名称", text: $vm.editPinboardName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13))
                                        .onSubmit {
                                            vm.saveEditingPinboard(appState: appState)
                                        }
                                    
                                    Button("保存") {
                                        vm.saveEditingPinboard(appState: appState)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(vm.editPinboardName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    
                                    Button("取消") {
                                        vm.cancelEditingPinboard()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("修改颜色：")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    let colors = ["#EF4444", "#F59E0B", "#10B981", "#3B82F6", "#8B5CF6", "#EC4899", "#6B7280"]
                                    ForEach(colors, id: \.self) { hex in
                                        Button {
                                            vm.editPinboardColorHex = hex
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: hex))
                                                    .frame(width: 16, height: 16)
                                                if vm.editPinboardColorHex == hex {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        } else {
                            PinboardSettingsRowView(
                                pinboard: pinboard,
                                index: index,
                                totalCount: appState.pinboards.count,
                                appState: appState,
                                vm: vm
                            )
                        }
                    }
                }
            }
            
            // Add New Pinboard Card
            settingsCard(title: "创建新分组") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("分组名称（例如：项目备忘、代码）", text: $vm.newPinboardName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onSubmit {
                                guard !vm.newPinboardName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                appState.addPinboard(
                                    name: vm.newPinboardName.trimmingCharacters(in: .whitespaces),
                                    colorHex: vm.selectedColorHex,
                                    iconName: "folder.fill"
                                )
                                vm.newPinboardName = ""
                            }
                        
                        Button {
                            guard !vm.newPinboardName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            appState.addPinboard(
                                name: vm.newPinboardName.trimmingCharacters(in: .whitespaces),
                                colorHex: vm.selectedColorHex,
                                iconName: "folder.fill"
                            )
                            vm.newPinboardName = ""
                        } label: {
                            Text("添加分组")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.newPinboardName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    HStack(spacing: 10) {
                        Text("选择颜色：")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        let colors = ["#EF4444", "#F59E0B", "#10B981", "#3B82F6", "#8B5CF6", "#EC4899", "#6B7280"]
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                vm.selectedColorHex = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 18, height: 18)
                                    if vm.selectedColorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Text("💡 提示：在主界面呼出时，您也可以点击底部的「+」直接新建分组，或使用 ⌘[ 与 ⌘] 快捷切换分组。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .alert("确定要删除分组“\(vm.pinboardToDelete?.name ?? "")”吗？", isPresented: $vm.showingDeletePinboardAlert) {
            Button("取消", role: .cancel) {
                vm.pinboardToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let board = vm.pinboardToDelete {
                    appState.deletePinboard(board)
                    vm.pinboardToDelete = nil
                }
            }
        } message: {
            Text("删除后，该分组中的卡片将保留在全部剪贴板历史中，不会被删除。")
        }
    }
    
    // MARK: - Privacy Tab (排除特定敏感应用与系统隐私保护)
    private var privacyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section 1: 已忽略的应用程序列表
            settingsCard(title: "已忽略的应用程序 (\(privacyManager.allIgnoredApps.count))") {
                ForEach(Array(privacyManager.allIgnoredApps.enumerated()), id: \.element.bundleId) { index, app in
                    if index > 0 {
                        cardDivider()
                    }
                    HStack(spacing: 12) {
                        appIconView(for: app)
                            .frame(width: 22, height: 22)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text(app.bundleId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if app.isCustom {
                            Text("自定义")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            Button {
                                privacyManager.removeCustomApp(bundleId: app.bundleId)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red.opacity(0.8))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("移除此应用的忽略规则")
                        } else {
                            Text("系统默认")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Section 2: 自主添加应用
            settingsCard(title: "添加要忽略的应用程序") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("您可以将任何应用程序加入排除名单。当从这些软件复制文本、图片或文件时，PasteFlow 将自动跳过，不保存到剪贴板历史中。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                    
                    HStack(spacing: 10) {
                        // Option 1: 从正在运行的应用选择
                        Menu {
                            let runningApps = privacyManager.getRunningApplications()
                            if runningApps.isEmpty {
                                Text("无其他未忽略的运行中应用")
                            } else {
                                ForEach(runningApps, id: \.bundleId) { runningApp in
                                    Button {
                                        privacyManager.addCustomApp(name: runningApp.name, bundleId: runningApp.bundleId)
                                    } label: {
                                        Text("\(runningApp.name) (\(runningApp.bundleId))")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("从运行中的应用选择...")
                            }
                        }
                        .menuStyle(.borderedButton)
                        
                        // Option 2: 浏览 /Applications 目录
                        Button {
                            privacyManager.selectAppFromDisk()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                Text("浏览应用文件夹 (.app)...")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    cardDivider()
                    
                    // Option 3: 手动输入 Bundle ID
                    HStack(spacing: 8) {
                        TextField("手动输入应用 Bundle Identifier（例如：com.example.myapp）", text: $vm.manualBundleId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        
                        Button("添加") {
                            guard !vm.manualBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let rawId = vm.manualBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                            privacyManager.addCustomApp(name: rawId, bundleId: rawId)
                            vm.manualBundleId = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.manualBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Section 3: 隐私保护安全标准
            settingsCard(title: "隐私保护安全标准") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("支持系统级瞬态与敏感数据标记")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("PasteFlow 遵循 macOS 隐私开发准则，当复制内容被源应用标记为 org.nspasteboard.TransientType 或 org.nspasteboard.ConcealedType（瞬态保密数据）时，将自动予以屏蔽，不会记录入历史。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    @ViewBuilder
    private func appIconView(for app: IgnoredApp) -> some View {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: app.isCustom ? "macwindow" : "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundColor(app.isCustom ? .blue : .purple)
        }
    }
    
    // MARK: - Accessibility Tab (系统辅助功能权限状态与操作)
    private var accessibilityView: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "权限状态") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: vm.isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(vm.isAccessibilityGranted ? .green : .orange)
                            .animation(.spring(response: 0.3), value: vm.isAccessibilityGranted)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vm.isAccessibilityGranted ? "辅助功能权限已启用" : "未获得辅助功能权限")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(vm.isAccessibilityGranted ? "PasteFlow 拥有直接模拟粘贴至各应用程序的完整权限。" : "PasteFlow 需要系统辅助功能权限以支持直接按 ⌘V 模拟粘贴。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button {
                                vm.refreshAccessibility()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                Text("刷新状态")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            if vm.isAccessibilityGranted {
                                Button {
                                    PasteManager.shared.openSystemAccessibilitySettings()
                                } label: {
                                    Text("管理权限...")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            } else {
                                Button {
                                    PasteManager.shared.openSystemAccessibilitySettings()
                                } label: {
                                    Text("前往授权...")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                        }
                    }
                    
                    cardDivider()
                    
                    Text("为什么需要此权限？\n当您在 PasteFlow 中选中历史卡片并点击粘贴时，应用需要模拟键盘事件向活动软件（如 Safari、微信、Xcode、WPS）发送粘贴指令。如果未授予权限，PasteFlow 仍会将内容复制到系统剪贴板，您可以手动按 ⌘V 粘贴。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            settingsCard(title: "授权指南与常见问题") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("1.")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text("点击上方「前往授权...」按钮，打开 macOS「系统设置 > 隐私与安全性 > 辅助功能」")
                                .font(.system(size: 12))
                        }
                        HStack(spacing: 8) {
                            Text("2.")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text("在应用列表中找到「PasteFlow」并打开其右侧的开关")
                                .font(.system(size: 12))
                        }
                    }
                    
                    cardDivider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("系统设置中已开启，但此处仍显示未获得？")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Text("这是 macOS 系统的权限缓存机制导致的（在应用更新安装后常见）。请在系统的「辅助功能」列表中：\n• 将 PasteFlow 的开关关闭一次再重新打开；\n• 或者选中 PasteFlow 点击底部的「-」号删除，然后再点击「+」重新添加并开启即可生效。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - About Tab (关于 PasteFlow、版本信息与技术支持)
    private var aboutView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Branding Header
            HStack(spacing: 18) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 72, height: 72)
                        Image(systemName: "clipboard.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("PasteFlow")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("v\(appVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                    }
                    
                    Text("优雅、极速、强大的 macOS 剪贴板历史助手")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("Bundle ID: com.ma.pasteflow · Build \(buildNumber)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            // Section 1: 软件更新 (原生 GitHub Releases 引擎)
            settingsCard(title: "软件更新") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前版本")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.primary)
                            Text("PasteFlow v\(appVersion) (Build \(buildNumber))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if updater.isDownloading {
                            ProgressView(value: updater.downloadProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(width: 140)
                        } else if updater.downloadURL != nil || updater.newVersionURL != nil {
                            Button {
                                updater.downloadAndInstall()
                            } label: {
                                Text(updater.downloadURL != nil ? "下载并安装更新" : "前往主页下载")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        } else {
                            Button {
                                updater.checkForUpdates(manual: true)
                            } label: {
                                Text(updater.isChecking ? "正在检查..." : "检查更新...")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(updater.isChecking)
                        }
                    }
                    
                    if let status = updater.updateStatus {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundColor(updater.newVersionString != nil && !updater.isDownloading ? .green : .secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            
            // Section 2: 技术支持与项目
            settingsCard(title: "支持与社区") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开源主页与代码仓库")
                            .font(.system(size: 13, weight: .regular))
                        Text("查看项目源码、更新日志与最新动态")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: "https://github.com/thesadboy/PasteFlow") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("访问 GitHub")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                
                cardDivider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("反馈与功能建议")
                            .font(.system(size: 13, weight: .regular))
                        Text("遇到问题或有新想法？欢迎随时向我们提交反馈")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: "https://github.com") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("反馈问题")
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                
                cardDivider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("快捷键快速指南")
                            .font(.system(size: 13, weight: .regular))
                        Text("⌘⇧V 唤醒面板 · ⌘1~9 快速粘贴 · ⌘[ ⌘] 切换分组")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            
            // Section 3: 隐私与免责
            settingsCard(title: "隐私声明与版权") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("100% 离线运行：所有剪贴板数据均保存在本地磁盘沙盒中，绝不上报或联网传输。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider().opacity(0.3)
                    
                    HStack {
                        Text("Copyright © 2026 PasteFlow. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                        Text("Designed for macOS")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Section 4: 应用程序操作
            settingsCard(title: "应用程序操作") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("退出 PasteFlow")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.red)
                        Text("如果您隐藏了菜单栏图标，可以在此处彻底退出应用")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Text("退出")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Reusable UI Components
    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func settingToggleRow(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn.wrappedValue) { val in
                    onChange?(val)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func cardDivider() -> some View {
        Divider()
            .opacity(0.3)
            .padding(.leading, 16)
    }
    
    @ViewBuilder
    private func shortcutRow(title: String, subtitle: String? = nil, shortcut: UserShortcut) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Button {
                    if vm.recordingShortcutId == shortcut.id {
                        vm.stopRecording()
                    } else {
                        vm.startRecording(for: shortcut.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if vm.recordingShortcutId == shortcut.id {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("按下快捷键")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                        } else {
                            Text(shortcut.isEmpty ? "无" : shortcut.displayString)
                                .font(.system(size: 12, weight: shortcut.isEmpty ? .regular : .semibold, design: .monospaced))
                                .foregroundColor(shortcut.isEmpty ? .secondary : .primary)
                        }
                    }
                    .frame(minWidth: 84, minHeight: 24)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(vm.recordingShortcutId == shortcut.id ? Color.blue : Color.gray.opacity(0.3), lineWidth: vm.recordingShortcutId == shortcut.id ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Clear / Delete 'x' button (identical to Paste's delete button)
                if !shortcut.isEmpty {
                    Button {
                        hotkeyManager.clearShortcut(id: shortcut.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                } else {
                    Color.clear
                        .frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Settings] Failed to update launch at login: \(error)")
            }
        }
    }
}

private class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd + W
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) && event.keyCode == 13 {
            self.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Settings Window Manager
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    private var windowController: NSWindowController?
    
    private override init() {
        super.init()
    }
    
    public func showSettingsWindow() {
        AppState.shared.hideOverlay()
        
        NSApp.setActivationPolicy(.regular)
        if let controller = windowController, let window = controller.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PasteFlow 设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView())
        
        let controller = NSWindowController(window: window)
        self.windowController = controller
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
