# ImageView

ImageView 是一款原生 macOS 图片浏览器，面向快速打开、同目录连续浏览和触控板优先操作。它可作为常用图片格式的默认打开应用。

## 当前功能

- 支持 JPEG、PNG、GIF、TIFF、BMP、HEIC、HEIF、WebP、AVIF 和 SVG。
- 从 Finder、拖放、最近项目或“打开”菜单载入图片；同目录自然排序浏览。
- 同时打开多个独立图片窗口；首张图片复用启动空窗口，关闭最后一个图片窗口自动退出应用。
- 键盘、菜单、页边控制和触控板横向滑动切换图片；放大时保留平移行为。
- 双指缩放、拖拽平移、适应窗口/实际大小切换和全屏浏览。
- 自动隐藏的 HUD、胶片栏与页边控制；胶片栏选中缩略图始终居中。
- 旋转、镜像、自由裁剪、保存、另存为和未保存编辑确认。
- 重命名、移到废纸篓、在 Finder 中显示、复制路径，以及外部文件变更检测。
- 最近项目、深色/浅色/跟随系统外观、信息面板和动画切换设置。
- 设置窗口可一键将选中的常用图片格式设为由 ImageView 默认打开。

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

## 安装到本机

```bash
scripts/install-app.sh
```

脚本会重新构建并安装到 `/Applications/ImageView.app`，然后启动已安装版本。

## 文档

- [产品需求文档](docs/superpowers/specs/2026-07-09-imageview-prd.md)
- [默认应用关联设计](docs/superpowers/specs/2026-07-11-default-image-app-settings-design.md)
- [多图片窗口设计](docs/superpowers/specs/2026-07-11-multiple-image-windows-design.md)
