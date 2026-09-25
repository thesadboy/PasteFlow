import AppKit
import SwiftUI

final class CardHoverModel: ObservableObject {
    @Published var isHovered: Bool = false
}

public struct ClipCardView: View {
    public let item: ClipItem
    public let index: Int
    public let shortcutIndex: Int?
    public let isSelected: Bool
    public let pinboards: [Pinboard]
    public let searchQuery: String
    public let onSelect: (Int) -> Void
    
    @StateObject private var hoverModel = CardHoverModel()
    
    public init(item: ClipItem, index: Int, shortcutIndex: Int? = nil, isSelected: Bool, pinboards: [Pinboard], searchQuery: String = "", onSelect: @escaping (Int) -> Void) {
        self.item = item
        self.index = index
        self.shortcutIndex = shortcutIndex ?? (index < 9 ? index : nil)
        self.isSelected = isSelected
        self.pinboards = pinboards
        self.searchQuery = searchQuery
        self.onSelect = onSelect
    }
    
    public var body: some View {
        let isRichText = item.type == .text && item.richTextData != nil
        let badgeIcon = isRichText ? "doc.richtext" : item.type.iconName
        let badgeTitle = isRichText ? "富文本" : item.type.title
        let badgeColor = isRichText ? Color.purple : item.type.themeColor
        
        VStack(spacing: 0) {
            // MARK: - Card Header
            HStack(spacing: 6) {
                // App Icon
                if let icon = item.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }
                
                // App Name & Timestamp
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.sourceAppName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(item.formattedTimeAgo)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Content Type Badge Pill
                HStack(spacing: 3) {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 8))
                    Text(badgeTitle)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.12))
                .cornerRadius(10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
                .opacity(0.2)
            
            // MARK: - Card Content Body
            Group {
                switch item.type {
                case .text:
                    TextPreviewView(text: item.plainText, richTextData: item.richTextData, itemId: item.id, query: searchQuery)
                case .code:
                    CodePreviewView(code: item.plainText, language: item.codeLanguage, query: searchQuery)
                case .image:
                    ImagePreviewView(fileName: item.imageFileName, width: item.imageWidth, height: item.imageHeight)
                case .color:
                    ColorPreviewView(hex: item.colorHex ?? item.plainText)
                case .link:
                    LinkPreviewView(urlString: item.linkURL ?? item.plainText, title: item.linkTitle, query: searchQuery)
                case .file:
                    FilePreviewView(title: item.plainText, count: item.fileCount, sizeString: item.formattedFileSize, filePaths: item.filePaths, query: searchQuery)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
                .opacity(0.2)
            
            // MARK: - Card Footer
            HStack {
                // Shortcut badge (1 ~ 9)
                if let sIdx = shortcutIndex {
                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(sIdx + 1)")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(isSelected ? Color(red: 0.2, green: 0.65, blue: 1.0) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? Color(red: 0.2, green: 0.65, blue: 1.0).opacity(0.15) : Color.secondary.opacity(0.12))
                    )
                }
                
                Spacer()
                
                // Item length / size
                Text(item.type == .file ? item.formattedFileSize : item.characterCountString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 210, height: 230)
        .background(
            ZStack {
                // Card base
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(hoverModel.isHovered ? 0.85 : 0.72))
                
                // Subtle gradient highlight
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(hoverModel.isHovered ? 0.12 : 0.05), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(
                color: isSelected ? Color(red: 0.2, green: 0.65, blue: 1.0).opacity(0.35) : Color.black.opacity(0.12),
                radius: isSelected ? 6 : 3,
                x: 0,
                y: 2
            )
        )
        // Selection / Hover border & glow
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected
                        ? Color(red: 0.2, green: 0.65, blue: 1.0)
                        : (hoverModel.isHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.12)),
                    lineWidth: isSelected ? 2.0 : 1.0
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering in
            if hoverModel.isHovered != hovering {
                hoverModel.isHovered = hovering
            }
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                PasteManager.shared.paste(item: item)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                onSelect(index)
            }
        )
        .onDrag {
            NSItemProvider(object: "pasteflow-item:\(item.id.uuidString)" as NSString)
        }
        // Context Menu
        .contextMenu {
            Button {
                PasteManager.shared.paste(item: item)
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            
            Button {
                PasteManager.shared.paste(item: item, plainTextOnly: true)
            } label: {
                Label("以纯文本粘贴", systemImage: "text.alignleft")
            }
            
            Button {
                PasteManager.shared.copyToClipboard(item: item)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Menu("添加到分组...") {
                Button("从分组移除") {
                    AppState.shared.assignItemToPinboard(item, pinboardId: nil)
                }
                
                Divider()
                
                ForEach(pinboards) { pinboard in
                    Button {
                        AppState.shared.assignItemToPinboard(item, pinboardId: pinboard.id)
                    } label: {
                        HStack {
                            Circle()
                                .fill(pinboard.color)
                                .frame(width: 8, height: 8)
                            Text(pinboard.name)
                        }
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                AppState.shared.deleteItem(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
