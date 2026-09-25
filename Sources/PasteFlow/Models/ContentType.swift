import SwiftUI

public enum ContentType: String, Codable, CaseIterable, Identifiable {
    case text
    case code
    case link
    case image
    case color
    case file
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .text: return "文本"
        case .code: return "代码"
        case .link: return "链接"
        case .image: return "图片"
        case .color: return "颜色"
        case .file: return "文件"
        }
    }
    
    public var iconName: String {
        switch self {
        case .text: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .image: return "photo.fill"
        case .color: return "paintpalette.fill"
        case .file: return "folder.fill"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .text: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .code: return Color(red: 0.65, green: 0.40, blue: 0.95)
        case .link: return Color(red: 0.20, green: 0.75, blue: 0.65)
        case .image: return Color(red: 0.95, green: 0.45, blue: 0.35)
        case .color: return Color(red: 0.95, green: 0.70, blue: 0.20)
        case .file: return Color(red: 0.30, green: 0.70, blue: 0.95)
        }
    }
}
