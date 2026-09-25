import AppKit
import SwiftUI

// MARK: - Text Preview
public struct TextPreviewView: View {
    public let text: String
    public let richTextData: Data?
    public let itemId: UUID?
    public let query: String
    
    public init(text: String, richTextData: Data? = nil, itemId: UUID? = nil, query: String = "") {
        self.text = text
        self.richTextData = richTextData
        self.itemId = itemId
        self.query = query
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let rich = RichTextHelper.renderRichText(data: richTextData, itemId: itemId) {
                if !query.isEmpty {
                    Text(HighlightTextHelper.highlight(attributedString: rich, query: query))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(rich)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                if !query.isEmpty {
                    Text(HighlightTextHelper.highlight(text: text, query: query))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(verbatim: text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Code Preview
public struct CodePreviewView: View {
    public let code: String
    public let language: String?
    public let query: String
    
    public init(code: String, language: String?, query: String = "") {
        self.code = code
        self.language = language
        self.query = query
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lang = language {
                HStack {
                    Text(lang)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                    Spacer()
                }
            }
            
            if !query.isEmpty {
                Text(HighlightTextHelper.highlight(text: code, query: query))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.9, green: 0.92, blue: 0.95))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(6)
            } else {
                Text(verbatim: code)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.9, green: 0.92, blue: 0.95))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(6)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image Preview
public struct ImagePreviewView: View {
    public let fileName: String?
    public let width: Int?
    public let height: Int?
    
    public init(fileName: String?, width: Int?, height: Int?) {
        self.fileName = fileName
        self.width = width
        self.height = height
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            AsyncThumbnailView(fileName: fileName, width: width, height: height)
            
            if let w = width, let h = height {
                Text("\(w) × \(h)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color Preview
public struct ColorPreviewView: View {
    public let hex: String
    
    public init(hex: String) {
        self.hex = hex
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex))
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color(hex: hex).opacity(0.35), radius: 8, x: 0, y: 4)
            
            Text(hex)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Link Preview
public struct LinkPreviewView: View {
    public let urlString: String
    public let title: String?
    public let query: String
    
    public init(urlString: String, title: String?, query: String = "") {
        self.urlString = urlString
        self.title = title
        self.query = query
    }
    
    private var displayTitle: AttributedString {
        let t = title ?? "链接"
        if !query.isEmpty {
            return HighlightTextHelper.highlight(text: t, query: query)
        }
        return AttributedString(t)
    }
    
    private var displayUrl: AttributedString {
        if !query.isEmpty {
            return HighlightTextHelper.highlight(text: urlString, query: query)
        }
        return AttributedString(urlString)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Text(displayUrl)
                .font(.system(size: 11))
                .foregroundColor(.blue)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Preview
public struct FilePreviewView: View {
    public let title: String
    public let count: Int?
    public let sizeString: String
    public let filePaths: [String]?
    public let query: String
    
    public init(title: String, count: Int?, sizeString: String, filePaths: [String]? = nil, query: String = "") {
        self.title = title
        self.count = count
        self.sizeString = sizeString
        self.filePaths = filePaths
        self.query = query
    }
    
    private var nativeFileIcon: NSImage? {
        if let first = filePaths?.first, FileManager.default.fileExists(atPath: first) {
            return NSWorkspace.shared.icon(forFile: first)
        }
        return nil
    }
    
    private var fileExtension: String {
        guard let first = filePaths?.first else { return "FILE" }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first, isDirectory: &isDir), isDir.boolValue {
            return "FOLDER"
        }
        let ext = URL(fileURLWithPath: first).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
    
    private var displayTitle: AttributedString {
        if !query.isEmpty {
            return HighlightTextHelper.highlight(text: title, query: query)
        }
        return AttributedString(title)
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let icon = nativeFileIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: (count ?? 1) > 1 ? "folder.fill" : "doc.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color(red: 0.3, green: 0.7, blue: 0.95))
                }
                
                // Extension or count badge
                Text((count ?? 1) > 1 ? "\(count!)" : fileExtension)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(4)
                    .offset(x: 4, y: 4)
            }
            .padding(.top, 4)
            
            Text(displayTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            if !sizeString.isEmpty {
                Text(sizeString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
