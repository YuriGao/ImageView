# ImageView 另存为设计

日期：2026-07-10
状态：已确认，待实现

## 行为

1. Edit 菜单新增 Save As…，快捷键 Cmd+Shift+S；仅在当前存在未保存编辑时启用。
2. 用户在标准 macOS 保存面板选择位置与目标格式：PNG、JPEG、TIFF、BMP，及系统提供写入器时的 HEIC/HEIF。
3. 默认文件名为原文件名加 `-edited`，默认格式为 PNG；原文件绝不被修改。
4. 成功后当前编辑状态视为已保存，浏览器切换到新文件并在同目录导航中选中新文件。
5. 取消面板或写入失败时保留当前编辑与未保存状态，并显示既有轻量错误提示。

## 实现边界

`ImageEditingService` 新增目标格式写入 API，继续使用临时文件加原子替换/移动。`ViewerViewModel` 在另存成功后更新导航 URL、缓存和元数据。`MainWindowController` 独自持有 NSSavePanel，避免 Core 层依赖 AppKit。

## 验收

覆盖可选写入格式、目标文件写入、成功后状态清理与取消/失败保留编辑；完整测试和 App bundle 构建必须通过。
