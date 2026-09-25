import Combine
import SwiftUI

public final class SearchBarViewModel: ObservableObject {
    @Published public var showingClearAlert: Bool = false
    @Published public var inputText: String = ""
    
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        // Debounce: only push to AppState 120ms after typing stops
        $inputText
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard self != nil else { return }
                AppState.shared.searchQuery = text
            }
            .store(in: &cancellables)
        
        // Sync back when AppState clears externally (ESC / hide)
        AppState.shared.$searchQuery
            .filter { $0.isEmpty }
            .sink { [weak self] _ in
                guard let self, !self.inputText.isEmpty else { return }
                self.inputText = ""
            }
            .store(in: &cancellables)
            
        // Sync alert state to AppState to isolate keyboard events
        $showingClearAlert
            .sink { showing in
                AppState.shared.isAlertPresented = showing
            }
            .store(in: &cancellables)
    }
}

public struct SearchBarView: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var vm = SearchBarViewModel()
    
    public init() {}

    
    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - Search Input Pill
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("搜索剪贴板...", text: $vm.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 140)
                
                if !vm.inputText.isEmpty {
                    Button {
                        vm.inputText = ""
                        appState.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .cornerRadius(14)
            
            // MARK: - Type Filter Menu
            Menu {
                Button {
                    appState.selectedTypeFilter = nil
                } label: {
                    HStack {
                        Text("全部类型")
                        if appState.selectedTypeFilter == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                ForEach(ContentType.allCases) { type in
                    Button {
                        appState.selectedTypeFilter = (appState.selectedTypeFilter == type) ? nil : type
                    } label: {
                        HStack {
                            Label(type.title, systemImage: type.iconName)
                            if appState.selectedTypeFilter == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: appState.selectedTypeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(appState.selectedTypeFilter == nil ? .secondary : Color(red: 0.2, green: 0.65, blue: 1.0))
                    .frame(width: 26, height: 26)
                    .background(appState.selectedTypeFilter == nil ? Color.white.opacity(0.08) : Color.blue.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // MARK: - Clear History Button
            Button {
                vm.showingClearAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .alert("您确定要删除剪贴板历史记录吗？", isPresented: $vm.showingClearAlert) {
                Button("取消", role: .cancel) {}
                Button("删除历史", role: .destructive) {
                    appState.clearHistory()
                }
            } message: {
                Text("已固定的项目和分组中的内容不会被删除。此操作无法撤销。")
            }
            
            // MARK: - Settings Menu
            Menu {
                Button {
                    appState.showSettings = true
                    NSApp.activate(ignoringOtherApps: true)
                    SettingsWindowManager.shared.showSettingsWindow()
                } label: {
                    Label("设置...", systemImage: "gearshape")
                }
                
                if appState.isMonitoringPaused {
                    Button {
                        appState.resumeMonitoring()
                    } label: {
                        Label("启用 PasteFlow (\(appState.pauseStatusDescription))", systemImage: "play.fill")
                    }
                    
                    Menu {
                        ForEach(PauseDuration.allCases) { duration in
                            Button(duration.title) {
                                appState.pauseMonitoring(for: duration)
                            }
                        }
                    } label: {
                        Label("调整暂停时长", systemImage: "clock.arrow.circlepath")
                    }
                } else {
                    Menu {
                        Button("暂停 10 分钟") {
                            appState.pauseMonitoring(for: .tenMinutes)
                        }
                        Button("暂停 15 分钟") {
                            appState.pauseMonitoring(for: .fifteenMinutes)
                        }
                        Button("暂停 30 分钟") {
                            appState.pauseMonitoring(for: .thirtyMinutes)
                        }
                        Button("暂停 1 小时") {
                            appState.pauseMonitoring(for: .oneHour)
                        }
                        Divider()
                        Button("永久暂停") {
                            appState.pauseMonitoring(for: .indefinitely)
                        }
                    } label: {
                        Label("暂停 PasteFlow", systemImage: "pause.fill")
                    }
                }
                
                Divider()
                
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出 PasteFlow", systemImage: "power")
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(appState.isMonitoringPaused ? .orange : .secondary)
                        .frame(width: 26, height: 26)
                        .background(appState.isMonitoringPaused ? Color.orange.opacity(0.18) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                    
                    if appState.isMonitoringPaused {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
