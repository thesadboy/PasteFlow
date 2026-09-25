# PasteFlow (com.ma.pasteflow)

原生 macOS 剪贴板管理软件，提供剪贴板历史、快速粘贴、内容分类与钉板等功能。

- **应用名称**：PasteFlow（流贴）
- **Bundle 标识符**：`com.ma.pasteflow`
- **官方网站**：[https://thesadboy.github.io/PasteFlow/](https://thesadboy.github.io/PasteFlow/)
- **构建产物**：`build/PasteFlow.app`

## 全新特性
1. **全局快捷键自定义**：进入「偏好设置 -> 快捷键」，点击快捷键按钮即可直接在键盘上按下新组合键（如 `⌥ Space`、`⌥ V` 等）即时生效，也支持一键「恢复默认」。
2. **原生文件复制与粘贴完整支持**：
   - 完美适配 macOS Finder 文件流转；
   - 自动识别真实文件路径，优先于图片检测；
   - 动态提取系统原生的文件类型图标（PDF、DMG、ZIP、代码文件等）与文件后缀角标；
   - 粘贴回目标软件时完整写入 `NSFilenamesPboardType` 与 `public.file-url`，可直接粘贴进 Finder、微信、桌面或终端。

## 快捷键速查
- **呼出 / 隐藏**：`⌘ ⇧ V` (支持在设置中自定义)
- **直接粘贴**：`↩` (Return) 或 双击卡片
- **纯文本粘贴**：`⇧ ↩` (Shift + Return)
- **快速粘贴前 9 项**：`⌘ 1` ~ `⌘ 9`
- **左右选择**：`←` / `→`
- **删除卡片**：`⌫` (Delete)
- **复制到剪贴板**：`⌘ C`
- **关闭面板**：`Esc`

## 脚本命令
- 运行：`./scripts/run.sh`
- 构建：`./scripts/build.sh`
