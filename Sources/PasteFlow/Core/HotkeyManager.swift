import AppKit
import Carbon
import Combine

// MARK: - Modifier Option Enum (100% 参照 Paste)
public enum ModifierOption: String, CaseIterable, Identifiable, Codable {
    case command = "command"
    case shift = "shift"
    case option = "option"
    case control = "control"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .command: return "⌘ Command"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        }
    }
    
    public func isPressed(flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .command: return flags.contains(.command)
        case .shift: return flags.contains(.shift)
        case .option: return flags.contains(.option)
        case .control: return flags.contains(.control)
        }
    }
}

// MARK: - Shortcut Model
public struct UserShortcut: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayString: String
    public var isGlobal: Bool
    
    public var isEmpty: Bool {
        return keyCode == 0 && modifiers == 0 && displayString.isEmpty
    }
    
    public init(
        id: String,
        title: String,
        keyCode: UInt32,
        modifiers: UInt32,
        displayString: String,
        isGlobal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
        self.isGlobal = isGlobal
    }
    
    public func matches(event: NSEvent) -> Bool {
        if isEmpty { return false }
        if event.keyCode != UInt16(keyCode) { return false }
        let eventMods = HotkeyManager.carbonModifiers(from: event.modifierFlags)
        let mask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return (eventMods & mask) == (modifiers & mask)
    }
}

// MARK: - Hotkey Manager
public final class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()
    
    @Published public var shortcuts: [UserShortcut] = []
    @Published public var quickPasteModifier: ModifierOption = .command {
        didSet {
            UserDefaults.standard.set(quickPasteModifier.rawValue, forKey: "quickPasteModifier")
        }
    }
    @Published public var plainTextModifier: ModifierOption = .shift {
        didSet {
            UserDefaults.standard.set(plainTextModifier.rawValue, forKey: "plainTextModifier")
        }
    }
    
    private var globalHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    
    // Default 4 shortcuts completely referencing Paste
    public static let defaultShortcuts: [UserShortcut] = [
        UserShortcut(id: "activatePaste", title: "启动 PasteFlow", keyCode: 0x09, modifiers: UInt32(cmdKey | shiftKey), displayString: "⌘ ⇧ V", isGlobal: true),
        UserShortcut(id: "activatePasteStack", title: "启动 Paste Stack", keyCode: 0x08, modifiers: UInt32(cmdKey | shiftKey), displayString: "⌘ ⇧ C", isGlobal: true),
        UserShortcut(id: "nextPinboard", title: "显示下一个分组", keyCode: 30, modifiers: 0, displayString: "]", isGlobal: false),
        UserShortcut(id: "previousPinboard", title: "显示上一个分组", keyCode: 33, modifiers: 0, displayString: "[", isGlobal: false)
    ]
    
    private init() {
        loadShortcuts()
    }
    
    // Convenience getters
    public var activatePasteShortcut: UserShortcut {
        shortcuts.first { $0.id == "activatePaste" } ?? Self.defaultShortcuts[0]
    }
    
    public var activatePasteStackShortcut: UserShortcut {
        shortcuts.first { $0.id == "activatePasteStack" } ?? Self.defaultShortcuts[1]
    }
    
    public var nextPinboardShortcut: UserShortcut {
        shortcuts.first { $0.id == "nextPinboard" } ?? Self.defaultShortcuts[2]
    }
    
    public var previousPinboardShortcut: UserShortcut {
        shortcuts.first { $0.id == "previousPinboard" } ?? Self.defaultShortcuts[3]
    }
    
    public var currentDisplayString: String {
        activatePasteShortcut.isEmpty ? "未设置" : activatePasteShortcut.displayString
    }
    
    // MARK: - Persistence
    
    public func loadShortcuts() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "userShortcuts"),
           let loaded = try? JSONDecoder().decode([UserShortcut].self, from: data),
           !loaded.isEmpty {
            self.shortcuts = loaded.map { sc in
                var updated = sc
                if sc.id == "nextPinboard" { updated.title = "显示下一个分组" }
                if sc.id == "previousPinboard" { updated.title = "显示上一个分组" }
                return updated
            }
        } else {
            self.shortcuts = Self.defaultShortcuts
        }
        
        if let qpRaw = defaults.string(forKey: "quickPasteModifier"),
           let qp = ModifierOption(rawValue: qpRaw) {
            self.quickPasteModifier = qp
        } else {
            self.quickPasteModifier = .command
        }
        
        if let ptRaw = defaults.string(forKey: "plainTextModifier"),
           let pt = ModifierOption(rawValue: ptRaw) {
            self.plainTextModifier = pt
        } else {
            self.plainTextModifier = .shift
        }
    }
    
    public func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: "userShortcuts")
        }
        UserDefaults.standard.set(quickPasteModifier.rawValue, forKey: "quickPasteModifier")
        UserDefaults.standard.set(plainTextModifier.rawValue, forKey: "plainTextModifier")
    }
    
    public func updateShortcut(id: String, keyCode: UInt32, modifiers: UInt32, displayString: String) {
        if let idx = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[idx].keyCode = keyCode
            shortcuts[idx].modifiers = modifiers
            shortcuts[idx].displayString = displayString
            saveShortcuts()
            
            if shortcuts[idx].isGlobal {
                registerGlobalHotkeys()
            }
        }
    }
    
    public func clearShortcut(id: String) {
        if let idx = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[idx].keyCode = 0
            shortcuts[idx].modifiers = 0
            shortcuts[idx].displayString = ""
            saveShortcuts()
            
            if shortcuts[idx].isGlobal {
                registerGlobalHotkeys()
            }
        }
    }
    
    public func resetToDefault() {
        self.shortcuts = Self.defaultShortcuts
        self.quickPasteModifier = .command
        self.plainTextModifier = .shift
        saveShortcuts()
        registerGlobalHotkeys()
    }
    
    // MARK: - Carbon Global Registration
    
    public func registerGlobalHotkeys() {
        unregisterGlobalHotkeys()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerCallback: EventHandlerUPP = { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            if let eventRef = eventRef {
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
            }
            
            DispatchQueue.main.async {
                if hotKeyID.id == 1 {
                    AppState.shared.toggleOverlay()
                } else if hotKeyID.id == 2 {
                    // Activate Paste Stack
                    AppState.shared.toggleOverlay()
                }
            }
            return noErr
        }
        
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        guard status == noErr else {
            print("[HotkeyManager] Failed to install event handler: \(status)")
            return
        }
        
        // Register each global shortcut if not empty
        for (index, shortcut) in shortcuts.filter({ $0.isGlobal }).enumerated() {
            if shortcut.isEmpty { continue }
            
            let hotKeyIdNum = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: OSType(0x50464C4F), id: hotKeyIdNum) // 'PFLO'
            var ref: EventHotKeyRef?
            
            let regStatus = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            
            if regStatus == noErr, let validRef = ref {
                globalHotKeyRefs[hotKeyIdNum] = validRef
                print("[HotkeyManager] Registered global hotkey \(shortcut.id): \(shortcut.displayString)")
            } else {
                print("[HotkeyManager] Failed to register global hotkey \(shortcut.id): \(regStatus)")
            }
        }
    }
    
    public func unregisterGlobalHotkeys() {
        for (_, ref) in globalHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        globalHotKeyRefs.removeAll()
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    // Backward compatibility for AppDelegate
    public func registerGlobalHotkey() {
        registerGlobalHotkeys()
    }
    
    public func unregisterGlobalHotkey() {
        unregisterGlobalHotkeys()
    }
    
    // MARK: - Key Conversion Helpers
    
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
    
    public static func displayString(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃ " }
        if flags.contains(.option) { result += "⌥ " }
        if flags.contains(.shift) { result += "⇧ " }
        if flags.contains(.command) { result += "⌘ " }
        result += keyString(for: keyCode)
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    public static func keyString(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "Key(\(keyCode))"
        }
    }
}
