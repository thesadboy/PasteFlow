import AppKit
import Combine
import SwiftUI

public enum PauseDuration: CaseIterable, Identifiable {
    case tenMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case indefinitely
    
    public var id: String { title }
    
    public var title: String {
        switch self {
        case .tenMinutes: return "暂停 10 分钟"
        case .fifteenMinutes: return "暂停 15 分钟"
        case .thirtyMinutes: return "暂停 30 分钟"
        case .oneHour: return "暂停 1 小时"
        case .indefinitely: return "永久暂停"
        }
    }
    
    public var seconds: TimeInterval? {
        switch self {
        case .tenMinutes: return 10 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .indefinitely: return nil
        }
    }
}

public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    @Published public var items: [ClipItem] = []
    @Published public var pinboards: [Pinboard] = []
    @Published public var selectedPinboardId: UUID? = nil // nil means "剪贴板历史"
    @Published public var searchQuery: String = ""
    @Published public var selectedTypeFilter: ContentType? = nil
    @Published public var selectedIndex: Int = 0
    @Published public var isOverlayVisible: Bool = false
    @Published public var showSettings: Bool = false
    @Published public var showNewPinboardSheet: Bool = false
    @Published public var isEditingGroup: Bool = false
    @Published public var isAlertPresented: Bool = false
    @Published public var isMonitoringPaused: Bool = false {
        didSet {
            ClipboardMonitor.shared.isPaused = isMonitoringPaused
            NotificationCenter.default.post(name: NSNotification.Name("PasteFlowPauseStatusChanged"), object: nil)
        }
    }
    @Published public var pausedUntil: Date? = nil
    private var pauseTimer: Timer?
    
    public var pauseStatusDescription: String {
        guard isMonitoringPaused else { return "运行中" }
        guard let until = pausedUntil else { return "已永久暂停" }
        let remaining = Int(ceil(until.timeIntervalSinceNow / 60))
        if remaining > 0 {
            return "剩余 \(remaining) 分钟"
        } else {
            return "即将恢复"
        }
    }
    
    public func pauseMonitoring(for duration: PauseDuration) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        if let sec = duration.seconds {
            let until = Date().addingTimeInterval(sec)
            pausedUntil = until
            let timer = Timer.scheduledTimer(withTimeInterval: sec, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resumeMonitoring()
                }
            }
            pauseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            pausedUntil = nil
        }
        isMonitoringPaused = true
    }
    
    public func resumeMonitoring() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pausedUntil = nil
        isMonitoringPaused = false
    }
    
    private let storage = StorageManager.shared
    
    private init() {
        self.items = storage.loadItems()
        self.pinboards = storage.loadPinboards()
        self.pruneExpiredHistory()
    }
    
    // MARK: - Filtered Items
    
    public var filteredItems: [ClipItem] {
        var list = items
        
        // 1. Filter by Pinboard
        if let pinId = selectedPinboardId {
            list = list.filter { $0.pinboardId == pinId }
        }
        
        // 2. Filter by Content Type
        if let type = selectedTypeFilter {
            list = list.filter { $0.type == type }
        }
        
        // 3. Filter by Search Query
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { item in
                if item.plainText.lowercased().contains(query) { return true }
                if item.sourceAppName.lowercased().contains(query) { return true }
                if let title = item.linkTitle, title.lowercased().contains(query) { return true }
                if let lang = item.codeLanguage, lang.lowercased().contains(query) { return true }
                if let hex = item.colorHex, hex.lowercased().contains(query) { return true }
                return false
            }
        }
        
        return list
    }
    
    public var selectedItem: ClipItem? {
        let currentFiltered = filteredItems
        guard !currentFiltered.isEmpty, selectedIndex >= 0, selectedIndex < currentFiltered.count else {
            return nil
        }
        return currentFiltered[selectedIndex]
    }
    
    // MARK: - Item Actions
    
    public func addNewItem(_ item: ClipItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if exact duplicate exists anywhere in the list
            if let idx = self.items.firstIndex(where: { $0.plainText == item.plainText && $0.type == item.type }) {
                var updated = self.items[idx]
                updated.createdAt = Date()
                // Preserve pin status and other metadata when updating a duplicate
                updated.isPinned = self.items[idx].isPinned
                updated.pinboardId = self.items[idx].pinboardId
                self.items.remove(at: idx)
                self.items.insert(updated, at: 0)
            } else {
                self.items.insert(item, at: 0)
            }
            
            // Apply history capacity limit
            self.enforceCapacityLimitInternal()
            
            // Reset selection to first item
            self.selectedIndex = 0
            self.pruneExpiredHistory()
            self.storage.scheduleSaveItems(self.items)
        }
    }
    
    public func promoteItem(_ item: ClipItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            
            var updatedItem = self.items[idx]
            updatedItem.createdAt = Date()
            
            self.items.remove(at: idx)
            self.items.insert(updatedItem, at: 0)
            
            self.selectedIndex = 0
            self.storage.scheduleSaveItems(self.items)
        }
    }
    
    public func pruneExpiredHistory() {
        let period: Int
        if let num = UserDefaults.standard.object(forKey: "historyRetentionIndex") as? NSNumber {
            period = num.intValue
        } else {
            period = 3
        }
        guard period < 4 else { return } // 4 is 永久 (Forever)
        
        let seconds: TimeInterval
        switch period {
        case 0: seconds = 86400 // 1天
        case 1: seconds = 7 * 86400 // 1周
        case 2: seconds = 30 * 86400 // 1个月
        case 3: seconds = 365 * 86400 // 1年
        default: return
        }
        
        let cutoff = Date().addingTimeInterval(-seconds)
        // Grouped items (pinboardId != nil) and pinned items (isPinned) are NEVER expired
        let expired = items.filter { $0.pinboardId == nil && !$0.isPinned && $0.createdAt < cutoff }
        if !expired.isEmpty {
            for item in expired {
                if let fileName = item.imageFileName {
                    storage.deleteImage(fileName: fileName)
                }
            }
            items.removeAll { $0.pinboardId == nil && !$0.isPinned && $0.createdAt < cutoff }
            if selectedIndex >= filteredItems.count {
                selectedIndex = max(0, filteredItems.count - 1)
            }
            storage.scheduleSaveItems(items)
        }
    }
    
    // MARK: - Capacity Limit Management
    
    public func enforceCapacityLimit() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.enforceCapacityLimitInternal()
            self.storage.scheduleSaveItems(self.items)
        }
    }
    
    private func enforceCapacityLimitInternal() {
        let limit = UserDefaults.standard.integer(forKey: "historyCapacityLimit")
        // -1: Unlimited, 0 (unset): default to 500
        let maxItems = limit > 0 ? limit : (limit == -1 ? Int.max : 500)
        guard maxItems < Int.max else { return }
        
        if items.count > maxItems {
            let protected = items.filter { $0.pinboardId != nil || $0.isPinned }
            let normal = items.filter { $0.pinboardId == nil && !$0.isPinned }
            let allowedNormal = max(0, maxItems - protected.count)
            let keptNormal = Array(normal.prefix(allowedNormal))
            let keptSet = Set(protected.map { $0.id }).union(keptNormal.map { $0.id })
            
            // Clean up orphan images for removed items
            let removedItems = items.filter { !keptSet.contains($0.id) }
            for it in removedItems {
                if let img = it.imageFileName {
                    storage.deleteImage(fileName: img)
                }
            }
            
            items = items.filter { keptSet.contains($0.id) }
            if selectedIndex >= filteredItems.count {
                selectedIndex = max(0, filteredItems.count - 1)
            }
        }
    }
    
    public func deleteItem(_ item: ClipItem) {
        if let fileName = item.imageFileName {
            storage.deleteImage(fileName: fileName)
        }
        items.removeAll { $0.id == item.id }
        if selectedIndex >= filteredItems.count {
            selectedIndex = max(0, filteredItems.count - 1)
        }
        storage.scheduleSaveItems(items)
    }
    
    public func clearHistory() {
        // Keep items in pinboards or pinned
        let itemsToDelete = items.filter { $0.pinboardId == nil && !$0.isPinned }
        for item in itemsToDelete {
            if let fileName = item.imageFileName {
                storage.deleteImage(fileName: fileName)
            }
        }
        items.removeAll { $0.pinboardId == nil && !$0.isPinned }
        selectedIndex = 0
        storage.saveItemsImmediately(items)
    }
    
    public func assignItemToPinboard(_ item: ClipItem, pinboardId: UUID?) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].pinboardId = pinboardId
            storage.scheduleSaveItems(items)
        }
    }
    
    public func addPinboard(name: String, colorHex: String, iconName: String) {
        let newBoard = Pinboard(name: name, colorHex: colorHex, iconName: iconName, order: pinboards.count)
        pinboards.append(newBoard)
        storage.savePinboards(pinboards)
    }
    
    public func updatePinboard(_ pinboard: Pinboard) {
        if let idx = pinboards.firstIndex(where: { $0.id == pinboard.id }) {
            pinboards[idx] = pinboard
            storage.savePinboards(pinboards)
        }
    }
    
    public func deletePinboard(_ pinboard: Pinboard) {
        // Unpin items assigned to this board
        for i in 0..<items.count {
            if items[i].pinboardId == pinboard.id {
                items[i].pinboardId = nil
            }
        }
        pinboards.removeAll { $0.id == pinboard.id }
        if selectedPinboardId == pinboard.id {
            selectedPinboardId = nil
        }
        normalizePinboardOrders()
        storage.savePinboards(pinboards)
        storage.scheduleSaveItems(items)
    }
    
    public func clearPinboardItems(_ pinboard: Pinboard) {
        for i in 0..<items.count {
            if items[i].pinboardId == pinboard.id {
                items[i].pinboardId = nil
            }
        }
        storage.scheduleSaveItems(items)
    }
    
    public func movePinboard(id sourceId: UUID, targetId: UUID) {
        guard sourceId != targetId,
              let fromIdx = pinboards.firstIndex(where: { $0.id == sourceId }),
              let origTargetIdx = pinboards.firstIndex(where: { $0.id == targetId }) else { return }
        
        let moved = pinboards.remove(at: fromIdx)
        let insertIndex = max(0, min(origTargetIdx, pinboards.count))
        pinboards.insert(moved, at: insertIndex)
        normalizePinboardOrders()
        storage.savePinboards(pinboards)
        print("[AppState] Moved pinboard '\(moved.name)' from index \(fromIdx) to \(insertIndex)")
    }
    
    public func movePinboard(id sourceId: UUID, toIndex targetIndex: Int) {
        guard let fromIdx = pinboards.firstIndex(where: { $0.id == sourceId }) else { return }
        let moved = pinboards.remove(at: fromIdx)
        let safeIndex = max(0, min(targetIndex, pinboards.count))
        pinboards.insert(moved, at: safeIndex)
        normalizePinboardOrders()
        storage.savePinboards(pinboards)
        print("[AppState] Moved pinboard '\(moved.name)' to index \(safeIndex)")
    }
    
    public func movePinboardToFront(id sourceId: UUID) {
        movePinboard(id: sourceId, toIndex: 0)
    }
    
    public func movePinboard(id sourceId: UUID, before targetId: UUID) {
        movePinboard(id: sourceId, targetId: targetId)
    }
    
    public func movePinboardLeft(_ pinboard: Pinboard) {
        guard let idx = pinboards.firstIndex(where: { $0.id == pinboard.id }), idx > 0 else { return }
        pinboards.swapAt(idx, idx - 1)
        normalizePinboardOrders()
        storage.savePinboards(pinboards)
    }
    
    public func movePinboardRight(_ pinboard: Pinboard) {
        guard let idx = pinboards.firstIndex(where: { $0.id == pinboard.id }), idx < pinboards.count - 1 else { return }
        pinboards.swapAt(idx, idx + 1)
        normalizePinboardOrders()
        storage.savePinboards(pinboards)
    }
    
    public func normalizePinboardOrders() {
        for i in 0..<pinboards.count {
            pinboards[i].order = i
        }
    }
    
    public func selectPreviousPinboard() {
        let allIds: [UUID?] = [nil] + pinboards.map { $0.id }
        guard allIds.count > 1 else { return }
        let currentIndex = allIds.firstIndex(of: selectedPinboardId) ?? 0
        let nextIndex = (currentIndex - 1 + allIds.count) % allIds.count
        selectedPinboardId = allIds[nextIndex]
        selectedIndex = 0
    }
    
    public func selectNextPinboard() {
        let allIds: [UUID?] = [nil] + pinboards.map { $0.id }
        guard allIds.count > 1 else { return }
        let currentIndex = allIds.firstIndex(of: selectedPinboardId) ?? 0
        let nextIndex = (currentIndex + 1) % allIds.count
        selectedPinboardId = allIds[nextIndex]
        selectedIndex = 0
    }
    
    // MARK: - Navigation & Paste Controls
    
    public func toggleOverlay() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
    
    public func showOverlay() {
        PasteManager.shared.recordPreviousApp()
        selectedIndex = 0
        isOverlayVisible = true
        OverlayPanel.shared.show()
    }
    
    public func hideOverlay(immediately: Bool = false) {
        isOverlayVisible = false
        isEditingGroup = false
        isAlertPresented = false
        searchQuery = ""
        if immediately {
            OverlayPanel.shared.hideImmediately()
        } else {
            OverlayPanel.shared.hide()
        }
    }
    
    public func selectNext() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }
    
    public func selectPrevious() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }
    
    public func pasteSelectedItem(plainTextOnly: Bool = false) {
        guard let item = selectedItem else { return }
        PasteManager.shared.paste(item: item, plainTextOnly: plainTextOnly)
    }
    
    public func pasteItem(at index: Int, plainTextOnly: Bool = false) {
        let currentFiltered = filteredItems
        guard index >= 0, index < currentFiltered.count else { return }
        PasteManager.shared.paste(item: currentFiltered[index], plainTextOnly: plainTextOnly)
    }
}
