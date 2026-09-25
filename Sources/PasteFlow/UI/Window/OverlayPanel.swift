import AppKit
import SwiftUI

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

public final class OverlayPanel: NSPanel {
    public static let shared = OverlayPanel()
    
    private let panelHeight: CGFloat = 310
    private var isAnimating: Bool = false
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    
    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = false
        self.acceptsMouseMovedEvents = false
        
        let hostingView = OverlayHostingView(rootView: OverlayMainView())
        hostingView.wantsLayer = true
        if let layer = hostingView.layer {
            layer.cornerRadius = 18
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.masksToBounds = true
        }
        self.contentView = hostingView
        self.initialFirstResponder = hostingView
    }
    
    override public var canBecomeKey: Bool {
        return true
    }
    
    override public var canBecomeMain: Bool {
        return false
    }
    
    // MARK: - Show & Hide Animations (120Hz GPU-Accelerated CoreAnimation Spring)
    
    public func show() {
        if isVisible && !isAnimating { return }
        
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        
        let screenFrame = targetScreen.frame
        let targetWidth = screenFrame.width
        let finalX = screenFrame.minX
        let finalY = screenFrame.minY
        
        let finalFrame = NSRect(x: finalX, y: finalY, width: targetWidth, height: panelHeight)
        let initialFrame = NSRect(x: finalX, y: finalY - panelHeight - 40, width: targetWidth, height: panelHeight)
        
        self.setFrame(initialFrame, display: false)
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        
        // Ensure search box does NOT automatically grab focus on open
        self.makeFirstResponder(self.contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.makeFirstResponder(self.contentView)
        }
        
        isAnimating = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
        
        setupClickMonitor()
        setupKeyMonitor()
    }
    
    public func hide() {
        if !isVisible && !isAnimating { return }
        
        removeClickMonitor()
        removeKeyMonitor()
        
        let finalY = self.frame.minY - panelHeight - 40
        let targetFrame = NSRect(x: self.frame.minX, y: finalY, width: self.frame.width, height: panelHeight)
        
        isAnimating = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.0, 0.7, 0.1)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.isAnimating = false
            StorageManager.shared.clearMemoryCache()
        })
    }
    
    /// Hides the panel immediately with zero animation delay, freeing focus for the paste target application.
    public func hideImmediately() {
        removeClickMonitor()
        removeKeyMonitor()
        self.alphaValue = 0.0
        self.orderOut(nil)
        self.isAnimating = false
        StorageManager.shared.clearMemoryCache()
    }
    
    private func setupClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            
            // Do not dismiss if a modal, alert, or group editor is active
            if AppState.shared.isEditingGroup || AppState.shared.isAlertPresented { return }
            if self.attachedSheet != nil || NSApp.modalWindow != nil { return }
            
            let clickPoint = NSEvent.mouseLocation
            
            // Check if click was inside OverlayPanel or any visible window/popover/sheet of our application
            let isInsideOurApp = NSApp.windows.contains { win in
                win.isVisible && win.frame.contains(clickPoint)
            }
            if !isInsideOurApp {
                AppState.shared.hideOverlay()
            }
        }
    }
    
    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            
            // 1. If user is editing a group or an alert/sheet is active, do NOT intercept any keys
            if AppState.shared.isEditingGroup || AppState.shared.isAlertPresented {
                return event
            }
            if self.attachedSheet != nil || NSApp.modalWindow != nil {
                return event
            }
            
            // 2. Only handle events specifically targeted at the OverlayPanel window itself.
            // If the event belongs to another window (e.g. Popover, Settings window, or dialog),
            // let that window handle its own keys natively (Return to submit, Esc to cancel, etc.).
            guard event.window === self else { return event }
            
            let handled = self.handleKeyDown(event: event)
            return handled ? nil : event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    // MARK: - Keyboard Navigation & Shortcut Dispatch
    
    private var isTextInputFocused: Bool {
        if AppState.shared.isEditingGroup || AppState.shared.isAlertPresented { return true }
        guard let responder = self.firstResponder else { return false }
        if responder === self || responder === self.contentView { return false }
        return responder is NSText || responder is NSTextView || responder is NSTextField
    }
    
    // Rename from override keyDown to a local handler
    private func handleKeyDown(event: NSEvent) -> Bool {
        if AppState.shared.isEditingGroup || AppState.shared.isAlertPresented {
            return false
        }
        
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        let appState = AppState.shared
        let hotkeyManager = HotkeyManager.shared
        let textFocused = isTextInputFocused
        
        // 1. ESC -> If searching/focused in search box, clear search query and defocus back to card deck; otherwise close panel
        if keyCode == 53 {
            if textFocused {
                appState.searchQuery = ""
                self.makeFirstResponder(self.contentView)
                return true
            }
            appState.hideOverlay()
            return true
        }
        
        // Cmd + , -> Open Settings
        if keyCode == 43 && modifiers.contains(.command) {
            SettingsWindowManager.shared.showSettingsWindow()
            return true
        }
        
        // 2. Left Arrow (123) / Right Arrow (124)
        if keyCode == 123 {
            if textFocused && appState.searchQuery.isEmpty {
                self.makeFirstResponder(self.contentView)
            }
            appState.selectPrevious()
            return true
        }
        if keyCode == 124 {
            if textFocused && appState.searchQuery.isEmpty {
                self.makeFirstResponder(self.contentView)
            }
            appState.selectNext()
            return true
        }
        
        // Check if Plain Text modifier is pressed
        let isPlainModifierDown = hotkeyManager.plainTextModifier.isPressed(flags: modifiers)
        
        // 3. Return (36) or Keypad Enter (76)
        if keyCode == 36 || keyCode == 76 {
            appState.pasteSelectedItem(plainTextOnly: isPlainModifierDown)
            return true
        }
        
        // 4. User-customized Pinboard Previous / Next navigation (defaults to [ and ])
        // If text input is focused, ONLY allow switching if a modifier key (Cmd/Ctrl) is pressed
        let hasNavModifier = modifiers.contains(.command) || modifiers.contains(.control)
        if !textFocused || hasNavModifier {
            if hotkeyManager.previousPinboardShortcut.matches(event: event) {
                appState.selectPreviousPinboard()
                return true
            }
            if hotkeyManager.nextPinboardShortcut.matches(event: event) {
                appState.selectNextPinboard()
                return true
            }
        }
        
        // 5. Quick Paste: modifier (default Cmd) + 1..9, or Single digit 1..9 (ONLY if search input is NOT focused)
        let numberKeyCodes: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8
        ]
        
        if let idx = numberKeyCodes[keyCode] {
            let isQuickModifierDown = hotkeyManager.quickPasteModifier.isPressed(flags: modifiers)
            if isQuickModifierDown || (!textFocused && appState.searchQuery.isEmpty) {
                appState.pasteItem(at: idx, plainTextOnly: isPlainModifierDown)
                return true
            }
        }
        
        // 6. Cmd + C -> Copy selected item (only when not copying text within input)
        if keyCode == 8 && modifiers.contains(.command) && !textFocused {
            if let item = appState.selectedItem {
                PasteManager.shared.copyToClipboard(item: item)
            }
            return true
        }
        
        // 7. Delete / Backspace (51)
        // CRITICAL ISOLATION: When text input is focused (search bar, etc.), Backspace
        // MUST NEVER delete a clip card! Always let the text field edit its content.
        if keyCode == 51 {
            if textFocused {
                return false
            } else {
                if let item = appState.selectedItem {
                    appState.deleteItem(item)
                }
                return true
            }
        }
        
        return false
    }
}
