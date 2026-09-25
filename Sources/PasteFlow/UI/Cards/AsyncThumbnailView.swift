import AppKit
import SwiftUI

public final class AsyncImageLoader: ObservableObject {
    @Published public var image: NSImage?
    @Published public var isLoading: Bool = false
    private var currentFileName: String?
    
    public init() {}
    
    public func load(fileName: String?) {
        guard let name = fileName, !name.isEmpty else {
            self.image = nil
            self.isLoading = false
            return
        }
        
        if currentFileName == name && image != nil {
            return
        }
        
        currentFileName = name
        
        // Fast path: memory cache hit (zero main thread disk I/O)
        if let fastImage = StorageManager.shared.memoryCachedImage(fileName: name) {
            self.image = fastImage
            self.isLoading = false
            return
        }
        
        self.isLoading = true
        StorageManager.shared.loadImageAsync(fileName: name) { [weak self] loadedImage in
            guard let self = self, self.currentFileName == name else { return }
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

public struct AsyncThumbnailView: View {
    public let fileName: String?
    public let width: Int?
    public let height: Int?
    
    @StateObject private var loader = AsyncImageLoader()
    
    public init(fileName: String?, width: Int? = nil, height: Int? = nil) {
        self.fileName = fileName
        self.width = width
        self.height = height
    }
    
    public var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 110)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            } else if loader.isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .frame(height: 100)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(height: 100)
            }
        }
        .onAppear {
            loader.load(fileName: fileName)
        }
        .onChange(of: fileName) { newFileName in
            loader.load(fileName: newFileName)
        }
    }
}
