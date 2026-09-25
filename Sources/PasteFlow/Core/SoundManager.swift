import AppKit
import AVFoundation

public final class SoundManager {
    public static let shared = SoundManager()
    
    private var copySound: NSSound?
    private var pasteSound: NSSound?
    
    private init() {
        loadSounds()
    }
    
    private func loadSounds() {
        // Look in main bundle, then module bundle, then local resource path
        let copyURL: URL? = Bundle.main.url(forResource: "Copy", withExtension: "aiff")
            ?? Bundle.module.url(forResource: "Copy", withExtension: "aiff")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Copy.aiff")
        
        let pasteURL: URL? = Bundle.main.url(forResource: "Paste", withExtension: "aiff")
            ?? Bundle.module.url(forResource: "Paste", withExtension: "aiff")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Paste.aiff")
        
        if let url = copyURL, FileManager.default.fileExists(atPath: url.path) {
            copySound = NSSound(contentsOf: url, byReference: true)
        }
        if let url = pasteURL, FileManager.default.fileExists(atPath: url.path) {
            pasteSound = NSSound(contentsOf: url, byReference: true)
        }
    }
    
    public func playCopySound() {
        guard UserDefaults.standard.object(forKey: "playSoundEffects") as? Bool ?? true else { return }
        DispatchQueue.main.async { [weak self] in
            self?.copySound?.stop()
            self?.copySound?.play()
        }
    }
    
    public func playPasteSound() {
        guard UserDefaults.standard.object(forKey: "playSoundEffects") as? Bool ?? true else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pasteSound?.stop()
            self?.pasteSound?.play()
        }
    }
}
