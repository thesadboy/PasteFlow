# PasteFlow 开发文档

> 本文档记录了 PasteFlow 项目的完整架构、功能决策、已知问题及解决方案，供换机/多人协作时快速接手开发。

---

## 项目简介

PasteFlow 是一款 macOS 剪贴板管理工具。通过菜单栏图标或快捷键 `Cmd+Shift+V` 唤出一个横向卡片弹层，展示剪贴板历史，支持搜索、分类、分组、快速粘贴等功能。

**当前版本：** v1.0.3 (Build 4)  
**技术栈：** Swift 5.9 + SwiftUI + AppKit + 原生 GitHub Releases API 升级引擎 (零外部依赖)  
**最低系统要求：** macOS 13.0 (Ventura)  
**构建方式：** Swift Package Manager (SPM)

---

## 目录结构

```
Paste/
├── Sources/PasteFlow/
│   ├── App/
│   │   ├── AppDelegate.swift       # 应用入口，初始化各 Manager
│   │   ├── AppState.swift          # 全局状态中心（单例）
│   │   └── PasteApp.swift          # SwiftUI App 入口
│   ├── Core/
│   │   ├── ClipboardMonitor.swift  # 剪贴板变化监听
│   │   ├── HotkeyManager.swift     # 全局快捷键管理
│   │   ├── PasteManager.swift      # 粘贴操作核心逻辑
│   │   ├── PrivacyManager.swift    # 隐私/权限相关
│   │   ├── SoundManager.swift      # 音效播放
│   │   └── StorageManager.swift    # 本地持久化（JSON）
│   ├── Models/
│   │   ├── ClipItem.swift          # 剪贴板条目数据模型
│   │   ├── ContentType.swift       # 内容类型枚举（text/image/code/color/link/file）
│   │   └── Pinboard.swift          # 分组模型
│   ├── UI/
│   │   ├── Cards/
│   │   │   ├── ClipCardView.swift  # 单张卡片视图
│   │   │   └── PreviewViews.swift  # 各类型内容预览（Text/Image/Code/Color/Link/File）
│   │   ├── MenuBar/                # 菜单栏图标和菜单
│   │   ├── Overlay/
│   │   │   ├── CardDeckView.swift  # 卡片横向滚动列表
│   │   │   ├── OverlayMainView.swift # 弹层主视图
│   │   │   ├── PinboardTabBar.swift  # 分组标签栏
│   │   │   └── SearchBarView.swift   # 搜索栏
│   │   ├── Settings/
│   │   │   └── SettingsView.swift    # 设置面板
│   │   └── Window/
│   │       ├── OverlayPanel.swift    # NSPanel 弹层窗口管理
│   │       └── VisualEffectView.swift # 毛玻璃背景
│   └── Resources/                    # 资源文件（图标、音效等）
├── scripts/
│   ├── build.sh    # 仅编译打包 .app
│   ├── run.sh      # 编译 + 安装到 /Applications + 启动（开发用）
│   └── dist.sh     # 编译 + 打包 DMG + 清理（发布用）
├── Resources/
│   └── Info.plist
└── Package.swift
```

---

## 核心架构

### AppState（全局状态中心）
`AppState.shared` 是整个应用的状态中心，采用 `ObservableObject`，所有 UI 层通过 SwiftUI 的 `@ObservedObject` 自动响应变化。

**关键属性：**
- `items: [ClipItem]` — 主历史数组，**按使用时间倒序排列**（最近在最前）
- `filteredItems: [ClipItem]` — 计算属性，根据 pinboard/type/searchQuery 过滤后的展示列表
- `selectedIndex: Int` — 当前选中的卡片在 `filteredItems` 中的索引
- `pinboards: [Pinboard]` — 分组列表

**关键方法：**
- `addNewItem(_ item:)` — 新增剪贴板项目（自动去重：同内容同类型则移动到第一位并刷新时间戳）
- `promoteItem(_ item:)` — 将已有项目提升到第一位（粘贴操作后调用）
- `pruneExpiredHistory()` — 根据设置中的历史保留时长清理过期数据

### PasteManager（粘贴核心）
负责实际的粘贴动作，通过 Accessibility API 模拟 `Cmd+V`。

**粘贴流程：**
1. 检查 `AXIsProcessTrusted()` 辅助功能权限
2. 将内容写入 `NSPasteboard`
3. 设置 `isSelfCopying = true`（防止 ClipboardMonitor 把自己写的内容当新项目）
4. 激活目标 App（`previousApp.activate()`）
5. 通过 `CGEvent` 注入 `Cmd+V` 按键事件（必须用 `cgSessionEventTap`，不能用 `cghidEventTap`）
6. 延迟 500ms 后重置 `isSelfCopying = false`
7. 调用 `AppState.shared.promoteItem(item)` 将该项目置顶

**权限说明：** 自动粘贴（模拟 Cmd+V）需要辅助功能权限。不同于剪贴板读写（不需要权限），CGEvent 注入必须有辅助功能授权。

### ClipboardMonitor（剪贴板监听）
使用定时器（`DispatchSourceTimer`，间隔约 0.5s）轮询 `NSPasteboard.general.changeCount`，检测到变化后：
1. 跳过 `PasteManager.isSelfCopying == true` 的自写入
2. 依次识别：文件 → 图片 → 文本（优先级顺序）
3. 生成 `ClipItem` 并调用 `AppState.shared.addNewItem()`

### OverlayPanel（弹层窗口）
继承自 `NSPanel`，设置了 `nonactivating` 样式，弹出时不会夺走其他 App 的焦点。键盘事件通过 `NSEvent.addLocalMonitorForEvents` 监听。

---

## 功能与实现决策

### 弹层触发
- 快捷键：`Cmd+Shift+V`（可在设置中自定义）
- 弹出时记录 `previousApp`（当前最前台的 App），用于粘贴时切换回目标 App

### 卡片类型识别（ClipboardMonitor）
识别优先级：**文件 > 图片 > 文本**
- **文件**：检测 `NSPasteboard.PasteboardType.fileURL`，聚合多文件信息
- **图片**：`NSImage(pasteboard:)` 成功且有 tiff 数据
- **文本**：`pasteboard.string(forType: .string)`，进一步细分为：
  - `code`：通过正则匹配关键字（`func`/`class`/`import` 等）
  - `color`：匹配 `#RRGGBB` 格式
  - `link`：以 `http://` 或 `https://` 开头
  - `text`：其余

### 粘贴目标模式（设置可切换）
- **activeApp**：粘贴到 previousApp（默认）
- **clipboard**：仅复制到剪贴板，不自动粘贴

### 历史置顶逻辑
粘贴某个项目后，该项目应立刻出现在历史的第一位：
1. `PasteManager.paste()` 完成后调用 `AppState.promoteItem(item)`
2. `promoteItem` 在 `DispatchQueue.main.async` 中操作 `items` 数组（线程安全）
3. 找到该 item 的 UUID，移除后插入到 index 0，同时刷新 `createdAt`

**注意**：`promoteItem` 内部**不要**再做 `removeAll(where:)` 的深度去重，否则在某些并发场景下会导致项目"被自己吃掉"、无法出现在第一位。

### 视图 ID 与 SwiftUI 懒加载
`CardDeckView` 中使用 `LazyHStack`，每张卡片的 SwiftUI 身份标识必须用 `item.id`（UUID），**不能用 index**：
```swift
// ✅ 正确
.id(item.id)

// ❌ 错误：导致 SwiftUI 视图缓存，置顶后视图不刷新
.id(index)
```
原因：用 index 时，SwiftUI 认为位置 0 的视图身份没变，不会重新渲染，只有滚出懒加载区域再回来才会显示正确内容。

### 双击粘贴手势
SwiftUI 中单击（`onTapGesture`）优先级高于 `simultaneousGesture`，会吞掉双击的第一次点击，导致双击永远无法触发。正确做法是把双击放在高优先级的 `.gesture` 中：
```swift
// ✅ 正确：双击优先
.gesture(TapGesture(count: 2).onEnded { /* paste */ })
.simultaneousGesture(TapGesture(count: 1).onEnded { /* select */ })

// ❌ 错误：单击会吞掉双击
.onTapGesture { /* select */ }
.simultaneousGesture(TapGesture(count: 2).onEnded { /* paste */ })
```

### 滚动性能优化
卡片阴影（`.shadow`）如果施加在整个卡片 VStack 上，SwiftUI 在滚动时需要为所有子视图内容（文字、图标、代码块）计算透明通道，帧率会骤降。
**解决方案**：将阴影移入背景 `ZStack` 的 `RoundedRectangle` 上，仅对纯色矩形做阴影计算。

### 辅助功能权限缓存 Bug
macOS 的 TCC 权限数据库缓存的是 App 的二进制签名。开发期间频繁重新编译覆盖后，虽然设置面板里 PasteFlow 是勾选的，`AXIsProcessTrusted()` 仍然返回 `false`。

**解法**：在系统设置 → 辅助功能中，选中 PasteFlow，点击 **"-"号删除**，然后重新添加并勾选。

**根本解决**：`run.sh` 现在会把 App 安装到 `/Applications/PasteFlow.app`，从固定路径启动，系统签名识别稳定，此 Bug 不再复现。

### 设置面板
使用 `NSWindowController` 管理，通过 `SettingsWindowManager.shared` 单例控制显示/隐藏。
- 打开设置时自动关闭剪贴板弹层
- 支持 `Cmd+W` 关闭设置面板（通过重写 `performClose`）
- 通过 `Cmd+,` 打开

---

## 键盘快捷键（弹层内）

| 按键 | 功能 |
|------|------|
| `←` / `→` | 切换选中卡片 |
| `Enter` / 数字键盘 Enter | 粘贴选中项 |
| `Escape` | 关闭弹层 |
| `Cmd+,` | 打开设置 |
| `[` / `]` | 切换分组（可在设置自定义） |
| `Cmd+1`~`9` | 快速粘贴第 N 张卡片 |
| `Modifier+Enter` | 以纯文本方式粘贴（modifier 可自定义） |

---

## 构建与发布

### 开发调试
```bash
./scripts/run.sh
```
- 编译（Release 模式）
- 安装到 `/Applications/PasteFlow.app`
- 启动 App

### 发布打包
```bash
./scripts/dist.sh
```
- 编译
- 生成 `dist/PasteFlow.dmg`（含 Applications 快捷方式，用户拖拽即可安装）
- 自动清理 `build/` 目录

### 环境要求
- macOS 13.0+ (开发机)
- Xcode Command Line Tools（`xcode-select --install`）
- Swift 5.9+

---

## 数据存储

存储路径：`~/Library/Application Support/PasteFlow/`
- `items.json` — 剪贴板历史（ClipItem 数组）
- `pinboards.json` — 分组配置
- `images/` — 图片类型的预览图（PNG）

通过 `StorageManager.shared` 统一读写，写入操作使用 `scheduleSaveItems`（防抖 0.5s，避免频繁 IO）。

---

## 设置项（UserDefaults Keys）

| Key | 类型 | 说明 | 默认值 |
|-----|------|------|--------|
| `historyLimit` | Int | 最大历史条数 | 500 |
| `historyRetentionIndex` | Int | 历史保留时长（0=1天/1=1周/2=1月/3=1年/4=永久） | 3（1年） |
| `pastePlainTextDefault` | Bool | 是否默认以纯文本粘贴 | false |
| `pasteTarget` | String | 粘贴目标（"activeApp" / "clipboard"） | "activeApp" |
| `playSounds` | Bool | 是否播放音效 | true |

---

## 交互与焦点隔离架构（Event & Focus Isolation）

为防止全局快捷键监听与文本输入、弹窗、气泡产生冲突，系统建立了四重隔离机制：

1. **窗口层级隔离（Window Isolation）**：
   - `OverlayPanel.setupKeyMonitor` 只拦截 `event.window === self` 的事件，属于子窗口（如 `NSPopoverWindow` 气泡、设置独立窗口）的按键由各窗口原生响应。
2. **模态与弹窗隔离（Modal & Alert Isolation）**：
   - 当处于分组编辑（`AppState.isEditingGroup`）、确认弹窗（`AppState.isAlertPresented`）或有附加 Sheet/Modal（`attachedSheet != nil || NSApp.modalWindow != nil`）时，快捷键监听完全放行。
3. **输入焦点与按键隔离（Text Input Isolation）**：
   - `OverlayPanel.isTextInputFocused` 自动检测当前第一响应者是否为文本输入控件（`NSTextView` / `NSText` / `NSTextField`）。
   - **Delete 键**：输入框获得焦点时绝对不拦截 Backspace，交由文本框删字；只有焦点在卡片流时才作为删除卡片快捷键。
   - **数字键 1~9**：输入框获得焦点时输入纯数字进行搜索；只有未聚焦输入框或按下 `⌘ + 1~9` 时才触发快捷粘贴。
   - **分组切换 `[` / `]`**：输入框获得焦点时输入符号；只有按下修饰键或未聚焦输入框时才切换分组。
   - **Esc 键**：输入框有内容时先清空搜索，搜索框为空时才关闭面板。
4. **全局点击安全判定（Click Monitor Isolation）**：
   - 全局点击关闭面板检测由单一的 `!self.frame.contains(clickPoint)` 改为遍历 `NSApp.windows`，只要点击发生在属于本应用的任意窗口（气泡、菜单、弹窗），均不触发外部失焦隐藏。

---

## 模拟自动粘贴稳定性保障机制（Paste Reliability Architecture）

偶发性粘贴失效（回车、数字快捷键、双击/右键点击均可能偶发）是 macOS 剪贴板工具的经典难题。经过深度时序排查，建立了 4 重全链路加固：

1. **零延迟面板隐藏（Zero-delay Panel Dismissal）**：
   - 正常点击空白处退出面板时保留平滑向下滑出动效（140ms）；
   - **触发粘贴时立即隐藏**（`hideOverlay(immediately: true)` 耗时 0ms 并立即 `orderOut`），避免悬浮面板在动画的 140ms 内争抢按键焦点，使 macOS Window Server 能第一时间将窗口焦点归还给目标应用。
2. **目标应用有效性与安全兜底（Effective Target App Resolution）**：
   - 过滤系统常驻界面守护进程（如 `ControlCenter`、`SystemUIServer`、`Spotlight` 等）；
   - 当 `previousApp` 意外为 nil 或已退出时，动态向下探测顶层前台可输入应用，杜绝向无效目标空发按键。
3. **纯净硬件级事件源隔离（HID System State Isolation）**：
   - 改用 `CGEventSource(stateID: .hidSystemState)` 构造 Cmd+V 事件，彻底切断物理键盘上残留按键（如快捷键唤起时手指未完全松开的 `Shift` 或 `Option`）被 OS 自动合成混入事件流，杜绝按键冲突。
4. **微秒级按键时序仿真（20ms Key Down/Up Gap）**：
   - 在 `KeyDown` 与 `KeyUp` 之间引入 20ms 微时钟间隔，防止 Chromium/Electron（VS Code、Slack、Chrome）或富文本编辑器的 RunLoop 将瞬间同时间戳的按下与抬起合并吞噬；
   - 同时向 `cghidEventTap` 与 `cgSessionEventTap` 双管道派发，保证全格式软件响应。

---

## 包体积构成与优化策略

应用采用**纯 Swift 原生架构**，彻底移除了第三方 Sparkle 依赖，安装包体积仅 **2.2MB**，常驻内存仅约 8MB：

| 组成部分 | 优化后体积 | 说明 |
| :--- | :--- | :--- |
| **`Contents/MacOS/PasteFlow`** | **1.2MB** | 经 `strip -u -r` 剥离调试符号与无效重定向表（减少 68%） |
| **`Contents/Resources`** | **1.7MB** | 包含 1024x1024 Retina 多分辨率 `AppIcon.icns`（1.6MB）与交互提示音（97KB） |
| **整体 DMG 安装包体积** | **2.2MB** | 极致精简，零外部三方动态库或框架 |

---

## 已知 Bug 与局限性

1. **辅助功能权限在开发时容易失效**：见上文"辅助功能权限缓存 Bug"
2. **无 Sandboxing**：目前未启用 App Sandbox，无法上架 Mac App Store，适合自签名分发。
3. **ClipboardMonitor 轮询**：基于定时器轮询而非系统推送，延迟约 0.5s，且持续占用少量 CPU（约 0.1% 以内）。

---

## 开发方向与完成记录

- [x] 分组管理（支持新建自动聚焦、回车创建、名称/颜色在线编辑与安全防清理）
- [x] 图片异步加载与内存二级缓存（基于 `ObservableObject` 规避 SPM 环境 `@State` 宏限制，后台异步解码 + 骨架加载占位）
- [x] 支持富文本（RTF / HTML）类型预览（自动适配深浅色模式对比度、防超大字号变形、独立“富文本”徽章）
- [x] 搜索结果高亮（支持关键词多词切分，对文本、富文本、代码、链接、文件名均做醒目高亮标注）
- [x] 原生 GitHub Releases API 在线更新（参照 MenuBarPulse 架构，支持后台版本比对、界面进度条、静默挂载 DMG 自动覆盖安装与重启）
- [x] 更丰富的分组管理（支持分组标签左右拖拽重排、卡片原生拖入分组与移出、右键快捷上下移动与清空、设置面板一键排序）
- [x] 底部设置按钮升级为下拉菜单（集成「设置...」、「暂停/启用 PasteFlow」、「退出 PasteFlow」，支持暂停状态橙点提示与全局同步）
- [x] 二次打开/重复运行唤醒（支持双击应用图标、Spotlight / 启动台再次打开时自动呼出底部弹窗面板）
- [x] 通用设置展示历史记录数量与存储空间占用（实时统计 Application Support 物理体积与普通/分组分布，支持在访达中一键打开）
- [x] 富文本双格式（RTF + HTML）自动互转与全格式写入（彻底解决 WPS、Office、网页富文本粘贴解析失败的问题）
- [x] 菜单栏图标升级为高精致度原生层叠符号（doc.on.clipboard 替换纯黑块状 clipboard.fill）
- [x] 最大历史容量可配置（通用设置支持 100/300/500/1000/2000/不限制，超量自动修剪并清理孤儿图片）
- [x] 暂停时长档位选择（支持 10分钟、15分钟、30分钟、1小时、永久暂停，到期自动倒计时恢复，并实时显示剩余时长）
- [x] 横向卡片滚动性能深度优化（禁用窗口级高频鼠标移动派发、消除卡片动态阴影重绘、规避 TextKit 2 繁重解析、ForEach 粒度优化，大幅降低滚动 CPU 占用）
- [x] Apple 通用剪贴板（接力 / Handoff）智能识别（精准识别来自 iPhone / iPad 的跨设备复制，显示专属设备图标与来源标签，避免错误识别为 Mac 前台应用）
- [x] 内存深度优化与低峰降级（ImageIO 缩略图下采样按需解码、应用图标按 BundleID 跨条目去重复用、弹窗关闭时自动释放内存缓存，常驻 Footprint 从 75MB+ 降至约 8.7MB）
- [ ] 国际化（i18n）支持
- [ ] iCloud 同步历史（需要 Entitlements）



