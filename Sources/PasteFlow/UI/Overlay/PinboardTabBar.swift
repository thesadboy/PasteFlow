import AppKit
import SwiftUI

public final class PinboardTabViewModel: ObservableObject {
    @Published public var showingNewBoardSheet: Bool = false
    @Published public var newBoardName: String = ""
    @Published public var newSelectedColorHex: String = "#3B82F6"
    
    @Published public var editingBoardId: UUID? = nil
    @Published public var editBoardName: String = ""
    @Published public var editSelectedColorHex: String = "#3B82F6"
    
    public init() {}
    
    public func startNew() {
        editingBoardId = nil
        newBoardName = ""
        newSelectedColorHex = "#3B82F6"
        AppState.shared.isEditingGroup = true
        showingNewBoardSheet = true
    }
    
    public func startEdit(_ board: Pinboard) {
        showingNewBoardSheet = false
        editBoardName = board.name
        editSelectedColorHex = board.colorHex
        AppState.shared.isEditingGroup = true
        editingBoardId = board.id
    }
    
    @Published public var pinboardToDelete: Pinboard? = nil
    @Published public var showingDeleteAlert: Bool = false
    
    @Published public var pinboardToClear: Pinboard? = nil
    @Published public var showingClearAlert: Bool = false
    
    public func requestDelete(_ pinboard: Pinboard) {
        pinboardToDelete = pinboard
        AppState.shared.isAlertPresented = true
        showingDeleteAlert = true
    }
    
    public func requestClear(_ pinboard: Pinboard) {
        pinboardToClear = pinboard
        AppState.shared.isAlertPresented = true
        showingClearAlert = true
    }
    
    public func finishEditing() {
        newBoardName = ""
        showingNewBoardSheet = false
        editingBoardId = nil
        AppState.shared.isEditingGroup = false
    }
}

public final class TabItemDropModel: ObservableObject {
    @Published public var isDropTargeted: Bool = false
    public init() {}
}

/// A native macOS text field wrapper that automatically requests first responder
/// and listens for the Return key to commit.
public struct AutoFocusTextField: NSViewRepresentable {
    public var placeholder: String
    @Binding public var text: String
    public var onCommit: () -> Void
    public var onCancel: (() -> Void)? = nil
    
    public init(
        placeholder: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onCommit = onCommit
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.onTextFieldAction(_:))
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = .systemFont(ofSize: 13)
        
        // Auto focus and select text shortly after entering window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            textField.window?.makeFirstResponder(textField)
            textField.selectText(nil)
        }
        return textField
    }
    
    public func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusTextField
        
        init(_ parent: AutoFocusTextField) {
            self.parent = parent
        }
        
        @objc func onTextFieldAction(_ sender: Any?) {
            parent.onCommit()
        }
        
        public func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }
        
        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel?()
                return true
            }
            return false
        }
    }
}

public struct PinboardEditorPopover: View {
    public let title: String
    public let confirmTitle: String
    @Binding public var name: String
    @Binding public var selectedColorHex: String
    public let presetColors: [String]
    public let onCancel: () -> Void
    public let onConfirm: () -> Void
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            
            AutoFocusTextField(
                placeholder: "分组名称",
                text: $name,
                onCommit: {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onConfirm()
                    }
                },
                onCancel: onCancel
            )
            .frame(width: 220, height: 24)
            
            Text("选择颜色")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(presetColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedColorHex == hex ? 2 : 0)
                        )
                        .onTapGesture {
                            selectedColorHex = hex
                        }
                }
            }
            
            HStack {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(confirmTitle) {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onConfirm()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

// MARK: - Drop Delegates
public struct GeneralHistoryTabDropDelegate: DropDelegate {
    @ObservedObject var dropModel: TabItemDropModel
    
    public func dropEntered(info: DropInfo) {
        dropModel.isDropTargeted = true
    }
    
    public func dropExited(info: DropInfo) {
        dropModel.isDropTargeted = false
    }
    
    public func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    public func performDrop(info: DropInfo) -> Bool {
        dropModel.isDropTargeted = false
        guard let provider = info.itemProviders(for: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"]).first else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { stringObj, _ in
            guard let str = stringObj as? String else { return }
            DispatchQueue.main.async {
                if str.hasPrefix("pasteflow-pinboard:") {
                    let idStr = String(str.dropFirst("pasteflow-pinboard:".count))
                    if let sourceId = UUID(uuidString: idStr),
                       let fromIdx = AppState.shared.pinboards.firstIndex(where: { $0.id == sourceId }),
                       fromIdx > 0 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            AppState.shared.movePinboardToFront(id: sourceId)
                            SoundManager.shared.playCopySound()
                        }
                    }
                } else if str.hasPrefix("pasteflow-item:") {
                    let idStr = String(str.dropFirst("pasteflow-item:".count))
                    if let itemId = UUID(uuidString: idStr),
                       let item = AppState.shared.items.first(where: { $0.id == itemId }) {
                        AppState.shared.assignItemToPinboard(item, pinboardId: nil)
                        SoundManager.shared.playCopySound()
                    }
                }
            }
        }
        return true
    }
}

public struct PinboardTabDropDelegate: DropDelegate {
    let pinboard: Pinboard
    @ObservedObject var dropModel: TabItemDropModel
    
    public func dropEntered(info: DropInfo) {
        dropModel.isDropTargeted = true
    }
    
    public func dropExited(info: DropInfo) {
        dropModel.isDropTargeted = false
    }
    
    public func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    public func performDrop(info: DropInfo) -> Bool {
        dropModel.isDropTargeted = false
        guard let provider = info.itemProviders(for: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"]).first else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { stringObj, _ in
            guard let str = stringObj as? String else { return }
            DispatchQueue.main.async {
                if str.hasPrefix("pasteflow-pinboard:") {
                    let idStr = String(str.dropFirst("pasteflow-pinboard:".count))
                    if let sourceId = UUID(uuidString: idStr) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            AppState.shared.movePinboard(id: sourceId, targetId: pinboard.id)
                            SoundManager.shared.playCopySound()
                        }
                    }
                } else if str.hasPrefix("pasteflow-item:") {
                    let idStr = String(str.dropFirst("pasteflow-item:".count))
                    if let itemId = UUID(uuidString: idStr),
                       let item = AppState.shared.items.first(where: { $0.id == itemId }) {
                        AppState.shared.assignItemToPinboard(item, pinboardId: pinboard.id)
                        SoundManager.shared.playCopySound()
                    }
                }
            }
        }
        return true
    }
}

// MARK: - General History Tab Item (Supports Card Drop to unassign & Pinboard Drop to move to front)
public struct GeneralHistoryTabItemView: View {
    public let isSelected: Bool
    @StateObject private var dropModel = TabItemDropModel()
    
    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
            Text("剪贴板历史")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isSelected ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.18) : (dropModel.isDropTargeted ? Color.white.opacity(0.25) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dropModel.isDropTargeted ? Color.white.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(dropModel.isDropTargeted ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: dropModel.isDropTargeted)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                AppState.shared.selectedPinboardId = nil
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            }
        )
        .onDrop(of: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"], delegate: GeneralHistoryTabDropDelegate(dropModel: dropModel))
        .help("点击查看全部剪贴板历史，支持将卡片拖动至此处移出分组")
    }
}

// MARK: - Individual Pinboard Tab Item
public struct PinboardTabItemView: View {
    public let pinboard: Pinboard
    public let isSelected: Bool
    public let canMoveLeft: Bool
    public let canMoveRight: Bool
    public let presetColors: [String]
    @ObservedObject public var vm: PinboardTabViewModel
    
    @StateObject private var dropModel = TabItemDropModel()
    
    public init(
        pinboard: Pinboard,
        isSelected: Bool,
        canMoveLeft: Bool,
        canMoveRight: Bool,
        presetColors: [String],
        vm: PinboardTabViewModel
    ) {
        self.pinboard = pinboard
        self.isSelected = isSelected
        self.canMoveLeft = canMoveLeft
        self.canMoveRight = canMoveRight
        self.presetColors = presetColors
        self.vm = vm
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pinboard.color)
                .frame(width: 8, height: 8)
            Text(pinboard.name)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isSelected ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? pinboard.color.opacity(0.2) : (dropModel.isDropTargeted ? pinboard.color.opacity(0.35) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dropModel.isDropTargeted ? pinboard.color : Color.clear, lineWidth: 2)
        )
        .scaleEffect(dropModel.isDropTargeted ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: dropModel.isDropTargeted)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                AppState.shared.selectedPinboardId = pinboard.id
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            }
        )
        .onDrag {
            NSItemProvider(object: "pasteflow-pinboard:\(pinboard.id.uuidString)" as NSString)
        }
        .onDrop(of: ["public.text", "public.utf8-plain-text", "public.plain-text", "NSStringPboardType"], delegate: PinboardTabDropDelegate(pinboard: pinboard, dropModel: dropModel))
        .help("按住并拖动可对分组重新排序；也可将卡片拖拽放入此分组")
        .contextMenu {
            Button {
                vm.startEdit(pinboard)
            } label: {
                Label("编辑分组...", systemImage: "pencil")
            }
            
            Divider()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    AppState.shared.movePinboardLeft(pinboard)
                }
            } label: {
                Label("向左移动", systemImage: "arrow.left")
            }
            .disabled(!canMoveLeft)
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    AppState.shared.movePinboardRight(pinboard)
                }
            } label: {
                Label("向右移动", systemImage: "arrow.right")
            }
            .disabled(!canMoveRight)
            
            Divider()
            
            Button {
                vm.requestClear(pinboard)
            } label: {
                Label("清空分组卡片...", systemImage: "xmark.bin")
            }
            
            Button(role: .destructive) {
                vm.requestDelete(pinboard)
            } label: {
                Label("删除分组...", systemImage: "trash")
            }
        }
        .popover(isPresented: Binding(
            get: { vm.editingBoardId == pinboard.id },
            set: { if !$0 { vm.finishEditing() } }
        )) {
            PinboardEditorPopover(
                title: "编辑分组",
                confirmTitle: "保存",
                name: $vm.editBoardName,
                selectedColorHex: $vm.editSelectedColorHex,
                presetColors: presetColors,
                onCancel: {
                    vm.finishEditing()
                },
                onConfirm: {
                    let trimmed = vm.editBoardName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        var updated = pinboard
                        updated.name = trimmed
                        updated.colorHex = vm.editSelectedColorHex
                        AppState.shared.updatePinboard(updated)
                        vm.finishEditing()
                    }
                }
            )
        }
    }
}

// MARK: - Main Pinboard Tab Bar
public struct PinboardTabBar: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var vm = PinboardTabViewModel()
    
    private let presetColors: [String] = [
        "#EF4444", "#F97316", "#F59E0B", "#10B981", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899"
    ]
    
    public init() {}
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // MARK: - General History Tab
                GeneralHistoryTabItemView(isSelected: appState.selectedPinboardId == nil)
                
                // MARK: - User Pinboards
                ForEach(Array(appState.pinboards.enumerated()), id: \.element.id) { index, pinboard in
                    PinboardTabItemView(
                        pinboard: pinboard,
                        isSelected: appState.selectedPinboardId == pinboard.id,
                        canMoveLeft: index > 0,
                        canMoveRight: index < appState.pinboards.count - 1,
                        presetColors: presetColors,
                        vm: vm
                    )
                }
                
                // MARK: - Add Pinboard Button
                Button {
                    vm.startNew()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { vm.showingNewBoardSheet },
                    set: { if !$0 { vm.finishEditing() } }
                )) {
                    PinboardEditorPopover(
                        title: "新建分组",
                        confirmTitle: "创建",
                        name: $vm.newBoardName,
                        selectedColorHex: $vm.newSelectedColorHex,
                        presetColors: presetColors,
                        onCancel: {
                            vm.finishEditing()
                        },
                        onConfirm: {
                            let trimmed = vm.newBoardName.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                appState.addPinboard(
                                    name: trimmed,
                                    colorHex: vm.newSelectedColorHex,
                                    iconName: "folder.fill"
                                )
                                vm.finishEditing()
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .alert("确定要删除分组“\(vm.pinboardToDelete?.name ?? "")”吗？", isPresented: Binding(
            get: { vm.showingDeleteAlert },
            set: {
                vm.showingDeleteAlert = $0
                AppState.shared.isAlertPresented = $0
                if !$0 { vm.pinboardToDelete = nil }
            }
        )) {
            Button("取消", role: .cancel) {
                vm.showingDeleteAlert = false
                vm.pinboardToDelete = nil
                AppState.shared.isAlertPresented = false
            }
            Button("删除", role: .destructive) {
                if let board = vm.pinboardToDelete {
                    AppState.shared.deletePinboard(board)
                    vm.pinboardToDelete = nil
                    vm.showingDeleteAlert = false
                    AppState.shared.isAlertPresented = false
                }
            }
        } message: {
            Text("删除后，该分组中的卡片将保留在全部剪贴板历史中，不会被删除。")
        }
        .alert("确定要清空“\(vm.pinboardToClear?.name ?? "")”中的所有卡片吗？", isPresented: Binding(
            get: { vm.showingClearAlert },
            set: {
                vm.showingClearAlert = $0
                AppState.shared.isAlertPresented = $0
                if !$0 { vm.pinboardToClear = nil }
            }
        )) {
            Button("取消", role: .cancel) {
                vm.showingClearAlert = false
                vm.pinboardToClear = nil
                AppState.shared.isAlertPresented = false
            }
            Button("清空", role: .destructive) {
                if let board = vm.pinboardToClear {
                    AppState.shared.clearPinboardItems(board)
                    vm.pinboardToClear = nil
                    vm.showingClearAlert = false
                    AppState.shared.isAlertPresented = false
                }
            }
        } message: {
            Text("卡片将从本分组中移出，仍安全保留在全部剪贴板历史中。")
        }
    }
}
