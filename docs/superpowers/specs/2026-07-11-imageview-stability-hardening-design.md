# ImageView Stability Hardening Design

日期：2026-07-11

状态：已批准实施

## 1. 目标

在不增加新产品功能、不引入大型第三方依赖的前提下，加固 ImageView 已有的图片浏览、渐进加载、缩放、GIF 播放、图片编辑保存、SVG 预览和外部文件刷新能力。

目标运行环境为两台 Apple Silicon Mac，系统均为 macOS 14 或更高。正式签名、公证、Intel 兼容、自动更新、图库管理和新的专业编辑能力不在范围内。

## 2. 约束

1. 保持 `ImageViewCore` 与 `ImageViewApp` 现有分层。
2. 不增加第三方 Swift Package。
3. 所有行为变更先写失败测试，再实现修复。
4. 保留现有支持格式和用户操作入口；无法正确渲染时明确失败，不允许静默输出残缺内容。
5. 大文件保护优先于完整播放：单个动画超过内存预算时允许退化为静态首帧。
6. 每项修复独立提交，完整测试和 App Bundle 构建作为最终门禁。

## 3. 交互与渐进加载

### 3.1 问题

预览图当前直接发布到可编辑的 `currentImage`。用户在完整图返回前编辑预览图时，完整图会覆盖像素，但不会同步清除未保存编辑状态。预览和完整图虽并发启动，却固定先等待预览，完整图先完成时也不能立即发布。

缩放 offset 以画布中心为原点，但缩放锚点公式按左上角坐标直接计算，导致中心缩放产生跳动。

### 3.2 设计

- `ViewerViewModel` 增加 `ImageLoadPhase`，取值为 `empty`、`preview`、`full`、`failed`。
- 只有 `full` 阶段允许旋转、镜像、裁剪和保存；ViewModel 方法与菜单验证同时执行门禁。
- 预览和完整图以任务组方式竞速发布。完整图完成后取消未完成预览；旧打开请求继续由 generation 校验隔离。
- 缩放前先把触点转换为相对 `bounds.midX/midY` 的坐标，再计算新 offset 并执行边界收敛。

## 4. GIF 内存控制

### 4.1 问题

完整 GIF 会一次性物化全部帧，但缓存只按主图成本计费，且 GIF 参与邻图后台预加载。大动画可能在尚未显示前占用大量内存。

### 4.2 设计

- `DecodedImage` 统一提供 `decodedByteCost`，包含主图及所有动画帧。
- `ImageCache` 直接根据 `DecodedImage` 计算成本，调用方不再传入容易出错的 cost。
- GIF 不参与邻图后台预加载。
- 动画帧解码预算为 128 MiB。解码前根据帧尺寸和帧数做保守估算；超过预算时保留首帧并将动画帧数组置空。
- 不在本次引入异步逐帧解码器；这会改变核心数据模型和播放管线，超出“修复现有风险”的必要范围。

## 5. 编辑保存与元数据

### 5.1 问题

当前保存路径只写入处理后的像素，EXIF、GPS、TIFF、IPTC、DPI 等源属性会丢失。由于显示像素已应用方向，直接复制原 orientation 还会造成二次旋转。

### 5.2 设计

- `ImageEditingService.save` 接收可选 `metadataSourceURL`。
- 从源文件读取图像属性，保留目标格式兼容的 EXIF、GPS、TIFF、IPTC、DPI 和颜色相关属性。
- 将根级和 TIFF orientation 统一为 1，更新输出像素尺寸，移除旧缩略图字段。
- 原地保存和另存为都传入当前源文件 URL；跨格式保存允许 ImageIO 过滤不兼容字段。
- 临时文件加原子替换策略保持不变。

## 6. SVG 正确性

### 6.1 问题

系统解码失败后的自研 SVG 回退仅支持第一个矩形和少量颜色，复杂 SVG 会被错误地渲染为残缺图片。

### 6.2 设计

- 保留 ImageIO 与 NSImage 两级系统解码。
- 删除部分 SVG XML 渲染器；系统无法正确解码时返回明确失败。
- 测试要求复杂 SVG 要么由系统完整解码，要么失败，不能只显示第一个元素。

## 7. 外部文件变化

### 7.1 问题

仅比较修改时间和文件大小不能识别同尺寸覆盖、保留 mtime 的原子替换等常见编辑器写入方式。

### 7.2 设计

- `CurrentFileVersion` 改用 POSIX `stat` 指纹：device、inode、size、mtime 纳秒和 ctime 纳秒。
- 保留窗口激活和每两秒检查机制，不增加持续全文件 Hash 或 FSEvents。

## 8. 构建质量

- 在 SwiftPM target 中明确排除由 `scripts/build-app.sh` 手工复制的 `Info.plist` 和 `ImageView.icns`，消除未处理资源警告。
- 最终验证包含 179 项既有测试、新增回归测试、Debug 构建、Release App Bundle 构建和应用包结构检查。

## 9. 验收标准

1. 预览阶段不能编辑；完整图先完成时立即显示；快速连续打开不串图。
2. 中心缩放 offset 保持为零，任意触点下的源像素在缩放前后保持不动。
3. GIF 缓存成本包含全部帧，超过 128 MiB 的动画不物化全部帧，也不在后台预加载。
4. JPEG/TIFF 编辑保存后方向、尺寸正确，EXIF/GPS/TIFF 基础字段可回读。
5. 复杂 SVG 不出现部分渲染成功。
6. 同尺寸原地改写和保留 mtime 的原子替换都能使缓存失效。
7. `swift test --disable-sandbox` 全量通过，`scripts/build-app.sh` 成功且无 SwiftPM 未处理资源警告。
