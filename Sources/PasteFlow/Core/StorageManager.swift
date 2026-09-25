import AppKit
import Foundation

public final class StorageManager {
    public static let shared = StorageManager()
    
    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let clipsURL: URL
    private let pinboardsURL: URL
    private let imagesDirectoryURL: URL
    
    private var saveWorkItem: DispatchWorkItem?
    private let queue: DispatchQueue = {
        let label = (Bundle.main.bundleIdentifier ?? "app") + ".storage"
        return DispatchQueue(label: label, qos: .utility)
    }()
    
    private init() {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportURL = root.appendingPathComponent("PasteFlow", isDirectory: true)
        clipsURL = appSupportURL.appendingPathComponent("clips.json")
        pinboardsURL = appSupportURL.appendingPathComponent("pinboards.json")
        imagesDirectoryURL = appSupportURL.appendingPathComponent("Images", isDirectory: true)
        
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Items Storage
    
    public func loadItems() -> [ClipItem] {
        guard fileManager.fileExists(atPath: clipsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: clipsURL)
            let items = try JSONDecoder().decode([ClipItem].self, from: data)
            return items
        } catch {
            print("[StorageManager] Error loading clips: \(error)")
            return []
        }
    }
    
    public func scheduleSaveItems(_ items: [ClipItem]) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: self.clipsURL, options: .atomic)
            } catch {
                print("[StorageManager] Error saving clips: \(error)")
            }
        }
        saveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    public func saveItemsImmediately(_ items: [ClipItem]) {
        saveWorkItem?.cancel()
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: self.clipsURL, options: .atomic)
            } catch {
                print("[StorageManager] Error saving clips: \(error)")
            }
        }
    }
    
    // MARK: - Pinboards Storage
    
    public func loadPinboards() -> [Pinboard] {
        guard fileManager.fileExists(atPath: pinboardsURL.path) else {
            let defaults = Pinboard.defaultPinboards
            savePinboards(defaults)
            return defaults
        }
        do {
            let data = try Data(contentsOf: pinboardsURL)
            let pinboards = try JSONDecoder().decode([Pinboard].self, from: data)
            return pinboards
        } catch {
            print("[StorageManager] Error loading pinboards: \(error)")
            return Pinboard.defaultPinboards
        }
    }
    
    public func savePinboards(_ pinboards: [Pinboard]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(pinboards)
                try data.write(to: self.pinboardsURL, options: .atomic)
            } catch {
                print("[StorageManager] Error saving pinboards: \(error)")
            }
        }
    }
    
    // MARK: - Image Storage
    
    private let memoryImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 25 * 1024 * 1024 // 25 MB max
        return cache
    }()
    
    public func saveImage(data: Data, id: UUID) -> String? {
        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            // Pre-cache downscaled thumbnail instead of full-resolution original
            if let thumb = downscaleThumbnail(data: data, maxPixelSize: 360) {
                memoryImageCache.setObject(thumb, forKey: fileName as NSString)
            }
            return fileName
        } catch {
            print("[StorageManager] Error saving image: \(error)")
            return nil
        }
    }
    
    public func memoryCachedImage(fileName: String) -> NSImage? {
        return memoryImageCache.object(forKey: fileName as NSString)
    }
    
    public func loadImage(fileName: String) -> NSImage? {
        if let cached = memoryImageCache.object(forKey: fileName as NSString) {
            return cached
        }
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let thumb = downscaleThumbnail(fileURL: fileURL, maxPixelSize: 360) else { return nil }
        memoryImageCache.setObject(thumb, forKey: fileName as NSString)
        return thumb
    }
    
    public func loadImageAsync(fileName: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = memoryImageCache.object(forKey: fileName as NSString) {
            completion(cached)
            return
        }
        
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard self.fileManager.fileExists(atPath: fileURL.path),
                  let thumb = self.downscaleThumbnail(fileURL: fileURL, maxPixelSize: 360) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.memoryImageCache.setObject(thumb, forKey: fileName as NSString)
            DispatchQueue.main.async {
                completion(thumb)
            }
        }
    }
    
    /// Downscale image to a lightweight thumbnail using ImageIO without fully decoding the high-res bitmap
    private func downscaleThumbnail(fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func downscaleThumbnail(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    /// Clears the in-memory image cache to release RAM when the popup hides or memory pressure occurs
    public func clearMemoryCache() {
        memoryImageCache.removeAllObjects()
    }
    
    public func deleteImage(fileName: String) {
        memoryImageCache.removeObject(forKey: fileName as NSString)
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }
    
    // MARK: - Storage Size & Management
    
    /// Calculates the total physical storage size used by PasteFlow in Application Support
    public func calculateStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: appSupportURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let rv = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                   rv.isRegularFile == true,
                   let size = rv.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }
    
    /// Returns human-readable storage size (e.g. "8.7 MB", "540 KB")
    public func formattedStorageSize() -> String {
        let bytes = calculateStorageSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Reveals the PasteFlow application support folder in Finder
    public func openStorageFolderInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appSupportURL.path)
    }
}
