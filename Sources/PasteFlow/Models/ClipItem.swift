import AppKit
import SwiftUI

public struct ClipItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var type: ContentType
    public var plainText: String
    public var richTextData: Data?
    public var htmlData: Data?
    
    // Source App metadata
    public var sourceAppName: String
    public var sourceAppBundleId: String?
    public var sourceAppIconData: Data?
    
    public var createdAt: Date
    public var pinboardId: UUID?
    public var isPinned: Bool
    
    // Content-specific metadata
    public var codeLanguage: String?
    public var linkURL: String?
    public var linkTitle: String?
    public var colorHex: String?
    public var imageFileName: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var filePaths: [String]?
    public var fileCount: Int?
    public var fileSize: Int64?
    
    public init(
        id: UUID = UUID(),
        type: ContentType,
        plainText: String,
        richTextData: Data? = nil,
        htmlData: Data? = nil,
        sourceAppName: String = "未知应用",
        sourceAppBundleId: String? = nil,
        sourceAppIconData: Data? = nil,
        createdAt: Date = Date(),
        pinboardId: UUID? = nil,
        isPinned: Bool = false,
        codeLanguage: String? = nil,
        linkURL: String? = nil,
        linkTitle: String? = nil,
        colorHex: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        filePaths: [String]? = nil,
        fileCount: Int? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.type = type
        self.plainText = plainText
        self.richTextData = richTextData
        self.htmlData = htmlData
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppIconData = sourceAppIconData
        self.createdAt = createdAt
        self.pinboardId = pinboardId
        self.isPinned = isPinned
        self.codeLanguage = codeLanguage
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.colorHex = colorHex
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.fileCount = fileCount
        self.fileSize = fileSize
    }
    
    // Formatted relative time
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
    
    public var formattedTimeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdAt)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else if interval < 172800 {
            return "昨天"
        } else {
            return Self.shortDateFormatter.string(from: createdAt)
        }
    }
    
    // Formatted exact time for tooltip
    public var formattedExactTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: createdAt)
    }
    
    // Formatted file size string
    public var formattedFileSize: String {
        guard let bytes = fileSize, bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
    
    // Character count info
    public var characterCountString: String {
        let count = plainText.count
        if count > 10000 {
            return String(format: "%.1f万字", Double(count) / 10000.0)
        }
        return "\(count) 字符"
    }
    
    // Cached App Icon NSImage — keyed by sourceAppBundleId or sourceAppName, so 100 clips from Chrome share a single NSImage instance in memory
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    
    public var appIconImage: NSImage? {
        guard let data = sourceAppIconData else { return nil }
        let key = (sourceAppBundleId ?? sourceAppName) as NSString
        if let cached = Self.iconCache.object(forKey: key) {
            return cached
        }
        if let image = NSImage(data: data) {
            Self.iconCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }
}
