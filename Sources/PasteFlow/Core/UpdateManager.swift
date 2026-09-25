import AppKit
import Foundation
import Sparkle

public final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = UpdateManager()
    
    @Published public var canCheckForUpdates: Bool = true
    
    private var updaterController: SPUStandardUpdaterController?
    
    private override init() {
        super.init()
        setupUpdater()
    }
    
    private func setupUpdater() {
        // Initialize SPUStandardUpdaterController with standard Sparkle UI
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.canCheckForUpdates = self.updaterController?.updater.canCheckForUpdates ?? true
    }
    
    public func checkForUpdates() {
        if let controller = updaterController {
            controller.checkForUpdates(nil)
        }
    }
    
    public var automaticallyChecksForUpdates: Bool {
        get {
            return updaterController?.updater.automaticallyChecksForUpdates ?? true
        }
        set {
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
    
    public var automaticallyDownloadsUpdates: Bool {
        get {
            return updaterController?.updater.automaticallyDownloadsUpdates ?? false
        }
        set {
            updaterController?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }
}
