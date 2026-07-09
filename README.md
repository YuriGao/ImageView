# ImageView

Native macOS image viewer intended to replace Preview for fast same-folder image browsing.

## Development

```bash
swift test
swift run ImageView
```

## Build App Bundle

```bash
scripts/build-app.sh
open .build/ImageView.app
```

The bundle declares common image document types so macOS can offer it as an image viewer.

The PRD lives at `docs/superpowers/specs/2026-07-09-imageview-prd.md`.
