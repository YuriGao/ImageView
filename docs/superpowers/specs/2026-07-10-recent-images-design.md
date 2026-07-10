# ImageView 最近打开图片设计

日期：2026-07-10
状态：已确认，待实现

## 行为

成功打开的图片写入系统最近文档列表。File 菜单新增 Open Recent 子菜单，最多展示 10 项，点击后走既有 `open(url:)`，因此未保存编辑确认保持一致。不存在或不可读的最近项仍通过既有错误态处理。

## 实现

AppDelegate 使用 `NSDocumentController.shared.noteNewRecentDocumentURL` 记录成功打开的 URL，并从 `recentDocumentURLs` 构建菜单。控制器在图片成功加载后通过回调通知 AppDelegate，避免将解码失败文件加入最近列表。
