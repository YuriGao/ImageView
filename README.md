# ImageView

ImageView 是一款原生 macOS 图片浏览器，面向快速打开、同目录连续浏览和触控板优先操作。它可作为常用图片格式的默认打开应用。

## 当前功能

- 支持 JPEG、PNG、GIF、TIFF、BMP、HEIC、HEIF、WebP、AVIF、SVG 和 Sony ARW（RAW；只读）。
- 从 Finder、拖放、最近项目或“打开”菜单载入图片；同目录自然排序浏览。
- 同时打开多个独立图片窗口；首张图片复用启动空窗口，关闭最后一个图片窗口自动退出应用。
- 键盘、菜单、页边控制和触控板横向滑动切换图片；放大时保留平移行为。
- 双指缩放、拖拽平移、适应窗口、适应宽度、实际大小、预设/自定义倍率和全屏浏览。
- 连续纵向阅读同目录图片，并可设置从左到右或从右到左的翻页方向。
- 自动隐藏的 HUD、胶片栏与页边控制；胶片栏选中缩略图始终居中。
- 图片画布、胶片栏、连续阅读和文件夹网格右键菜单，以及标题栏“更多”菜单、一次性使用提示和可搜索帮助，让常用操作保持可见且易于查找。
- 旋转、镜像、自由裁剪、20 步撤销/重做、保存、另存为和未保存编辑确认；ARW 原始文件保持只读。
- 复制图像、复制路径、重命名、移到废纸篓、在 Finder 中显示，以及外部文件变更检测。
- 文件夹浏览模式支持搜索、格式过滤、排序、多选，以及批量移到废纸篓、移动和重命名。
- 批量任务提供逐项进度、取消、失败详情和安全冲突处理；可靠的移动与重命名操作支持一次性撤销。
- 可浮动或停靠的信息面板展示文件、尺寸、颜色和常用 EXIF 元数据，并支持复制字段和在 Finder 中显示。
- 最近项目、深色/浅色/跟随系统外观、动画开关，以及跟随系统“减少动态效果”的无障碍体验。
- 设置窗口可一键将选中的常用图片格式设为由 ImageView 默认打开。

## 系统要求

- macOS 14.0 或更高版本。
- 从源码构建需要 Swift 6 工具链。

## 下载并安装 Release

不需要配置开发环境时，可以直接使用 GitHub Actions 自动构建的 Release 安装包：

1. 打开 [GitHub Releases](https://github.com/YuriGao/ImageView/releases/latest)。
2. 在对应版本的 **Assets** 中下载 `ImageView.dmg`。
3. 打开 DMG，将 `ImageView.app` 拖入 `Applications` 文件夹。
4. 从“应用程序”文件夹启动 ImageView。

请只从本仓库的 GitHub Releases 页面下载安装包。

### 关于签名和首次打开

当前 Release 中的 `ImageView.app` 带有 **ad-hoc（临时）代码签名**，用于保持应用包代码签名结构完整。该签名不包含 Apple Developer ID 身份，DMG 也未经过 Apple 公证，因此它不等同于 Apple 官方认可的开发者签名分发。

从网络下载后，macOS Gatekeeper 可能提示无法验证开发者或阻止首次运行。确认安装包来自本仓库后，可使用以下任一方式首次打开：

- 在 Finder 的“应用程序”文件夹中按住 Control 键点按 `ImageView.app`，选择“打开”，然后再次确认。
- 如果系统仍然拦截，前往“系统设置”→“隐私与安全性”，在安全提示处选择“仍要打开”。

首次确认后，后续通常可以正常启动。未来如果 Release 改用 Apple Developer ID 签名并完成公证，此处会同步更新。

### Release 的构建方式

推送以 `v` 开头的版本标签后，GitHub Actions 会在 GitHub 托管的 macOS 环境中：

1. 使用 Release 配置编译 ImageView。
2. 组装并临时签名 `ImageView.app`。
3. 创建 `ImageView.dmg`。
4. 创建对应的 GitHub Release，并将 DMG 同时上传到 Release 和 Actions Artifact。

## 开发

```bash
swift test --disable-sandbox
swift run ImageView
```

## 构建应用包

```bash
scripts/build-app.sh
open .build/ImageView.app
```

构建产物为 `.build/ImageView.app`。应用包声明了上述图片类型，macOS 可将其作为候选默认图片查看器。

## 从源码安装到本机

```bash
scripts/install-app.sh
```

脚本会重新构建并安装到 `/Applications/ImageView.app`，然后启动已安装版本。

## 性能基准

```bash
scripts/run-memory-benchmarks.sh
```

脚本会生成小图、大图、动图和千图目录四类测试素材，构建应用并将内存基准写入 `docs/assets/performance/`。

## 文档

- [产品需求文档](docs/superpowers/specs/2026-07-09-imageview-prd.md)
- [默认应用关联设计](docs/superpowers/specs/2026-07-11-default-image-app-settings-design.md)
- [多图片窗口设计](docs/superpowers/specs/2026-07-11-multiple-image-windows-design.md)
- [辅助功能发布检查](docs/qa/2026-07-15-accessibility-validation.md)
- [内存基准示例](docs/assets/performance/memory-baseline-2026-07-15-113013.md)

## Support

ImageView is open source and free to use. If it helps you, you can support the project via Alipay:

<img src="docs/assets/alipay-qr.jpg" alt="Alipay donation QR code" width="220">

## 开源许可

本项目基于 [MIT License](LICENSE) 开源。
