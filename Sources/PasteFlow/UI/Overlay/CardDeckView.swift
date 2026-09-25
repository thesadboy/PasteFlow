import SwiftUI

public struct CardDeckView: View {
    @ObservedObject private var appState = AppState.shared
    
    public var body: some View {
        let items = appState.filteredItems
        let pinboards = appState.pinboards
        let selectedIndex = appState.selectedIndex
        
        if items.isEmpty {
            emptyStateView
        } else {
            let selectedItemId = (selectedIndex >= 0 && selectedIndex < items.count) ? items[selectedIndex].id : nil
            let topShortcuts: [UUID: Int] = {
                var map = [UUID: Int]()
                for (i, it) in items.prefix(9).enumerated() {
                    map[it.id] = i
                }
                return map
            }()
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { item in
                            let sIdx = topShortcuts[item.id]
                            ClipCardView(
                                item: item,
                                index: sIdx ?? 99,
                                shortcutIndex: sIdx,
                                isSelected: item.id == selectedItemId,
                                pinboards: pinboards,
                                searchQuery: appState.searchQuery,
                                onSelect: { _ in
                                    if let actualIdx = items.firstIndex(where: { $0.id == item.id }) {
                                        AppState.shared.selectedIndex = actualIdx
                                    }
                                    NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
                    }
                )
                .onChange(of: appState.selectedIndex) { newIndex in
                    guard newIndex >= 0, newIndex < items.count else { return }
                    let targetId = items[newIndex].id
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8, blendDuration: 0.1)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            if appState.selectedPinboardId != nil {
                Image(systemName: "folder")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("分组为空")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("右键剪贴板历史中的任意卡片，选择「添加到分组...」即可归类常用项目。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else if !appState.searchQuery.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("未找到相关内容")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("换个关键词搜索试试看。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("剪贴板历史记录为空")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("在任意软件中按 ⌘C 复制文本、链接、颜色或图片，它们会自动保存在这里。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
