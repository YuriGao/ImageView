# App Icon Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ImageView's current illustrated icon with a polished glass-viewfinder macOS icon and ship a valid ICNS resource.

**Architecture:** Generate one 1024 × 1024 PNG master with the built-in image generation tool, inspect it visually and at reduced sizes, then derive a complete macOS iconset and compile it with `iconutil`. Keep the existing resource names so the build script and `Info.plist` need no code changes.

**Tech Stack:** Built-in `imagegen`, PNG, macOS `sips`, `iconutil`, Swift Package Manager build script

## Global Constraints

- Use a dark smoked-glass rounded-square base with a simplified photo frame and mountain-light symbol.
- Use restrained blue, violet, and cyan edge highlights with subtle metallic depth.
- Do not include text, watermarks, camera bodies, realistic lenses, or complex landscape illustration.
- Deliver a 1024 × 1024 PNG master and a valid `ImageView.icns`.
- Preserve the resource paths `Sources/ImageViewApp/Resources/AppIcon-master.png` and `Sources/ImageViewApp/Resources/ImageView.icns`.

---

### Task 1: Generate and approve the PNG master

**Files:**
- Modify: `Sources/ImageViewApp/Resources/AppIcon-master.png`

**Interfaces:**
- Consumes: the approved visual specification in `docs/superpowers/specs/2026-07-11-app-icon-redesign.md`
- Produces: a square 1024 × 1024 RGBA or RGB PNG suitable as the source for every macOS icon size

- [ ] **Step 1: Generate the candidate with the built-in image tool**

Use this production prompt:

```text
Use case: logo-brand
Asset type: native macOS application icon for a fast, minimal image viewer
Primary request: create a premium glass-viewfinder app icon that clearly communicates viewing images
Scene/backdrop: a self-contained macOS rounded-square icon with a dark smoked-glass base
Subject: a bold simplified photo-frame symbol containing one abstract mountain ridge and a small light disc; the photo frame is the unmistakable primary silhouette
Style/medium: polished dimensional 3D icon, native macOS design language, restrained and professional
Composition/framing: centered, symmetrical visual balance, large readable central mark, generous safe margin, strong silhouette at 16–64 px
Lighting/mood: soft studio lighting, subtle cyan and blue-violet rim highlights, controlled reflections, quiet premium mood
Color palette: graphite black, deep navy, cool cyan, restrained violet; avoid saturated rainbow colors
Materials/textures: smoked glass, finely brushed dark metal, subtle translucent depth
Constraints: square 1024 x 1024 composition; no text; no watermark; no detached background; no mockup scene; no drop shadow outside the icon; retain simple readable shapes
Avoid: camera body, realistic camera lens, aperture blades, detailed landscape painting, game-art look, neon overload, excessive glow, tiny decoration, photoreal scenery
```

- [ ] **Step 2: Inspect the full-size output**

Open the generated image and confirm: the photo-frame silhouette reads first, the image-viewing concept is clear, the glass and metal effects remain restrained, and none of the avoid items appear.

- [ ] **Step 3: Copy the selected output into the project**

Copy the generated PNG to:

```text
Sources/ImageViewApp/Resources/AppIcon-master.png
```

Confirm its properties:

```bash
sips -g pixelWidth -g pixelHeight -g format Sources/ImageViewApp/Resources/AppIcon-master.png
```

Expected: width `1024`, height `1024`, format `png`.

- [ ] **Step 4: Verify small-size readability**

```bash
mkdir -p /tmp/imageview-icon-check
sips -z 64 64 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/imageview-icon-check/icon-64.png
sips -z 32 32 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/imageview-icon-check/icon-32.png
```

Inspect both outputs and confirm the photo-frame outline and internal mountain remain distinguishable without relying on fine texture.

### Task 2: Build and validate the ICNS resource

**Files:**
- Modify: `Sources/ImageViewApp/Resources/ImageView.icns`

**Interfaces:**
- Consumes: the approved 1024 × 1024 `AppIcon-master.png` from Task 1
- Produces: a macOS ICNS containing 16, 32, 128, 256, 512, and 1024-pixel representations

- [ ] **Step 1: Create the required iconset representations**

```bash
mkdir -p /tmp/ImageView.iconset
sips -z 16 16 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_16x16.png
sips -z 32 32 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_16x16@2x.png
sips -z 32 32 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_32x32.png
sips -z 64 64 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_32x32@2x.png
sips -z 128 128 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_128x128.png
sips -z 256 256 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_128x128@2x.png
sips -z 256 256 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_256x256.png
sips -z 512 512 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_256x256@2x.png
sips -z 512 512 Sources/ImageViewApp/Resources/AppIcon-master.png --out /tmp/ImageView.iconset/icon_512x512.png
cp Sources/ImageViewApp/Resources/AppIcon-master.png /tmp/ImageView.iconset/icon_512x512@2x.png
```

- [ ] **Step 2: Compile the iconset**

```bash
iconutil -c icns /tmp/ImageView.iconset -o Sources/ImageViewApp/Resources/ImageView.icns
```

Expected: command exits successfully and `file Sources/ImageViewApp/Resources/ImageView.icns` identifies a macOS icon.

- [ ] **Step 3: Build the application bundle**

```bash
scripts/build-app.sh
```

Expected: exit code `0` and final output ending in `.build/ImageView.app`.

- [ ] **Step 4: Confirm the built bundle contains the new icon**

```bash
cmp Sources/ImageViewApp/Resources/ImageView.icns .build/ImageView.app/Contents/Resources/ImageView.icns
```

Expected: exit code `0` with no output.

- [ ] **Step 5: Commit the final assets**

```bash
git add Sources/ImageViewApp/Resources/AppIcon-master.png Sources/ImageViewApp/Resources/ImageView.icns
git commit -m "feat: redesign app icon"
```
