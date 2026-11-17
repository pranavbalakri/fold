# Fold

A native macOS utility for converting files and bringing PDFs together. Built with SwiftUI and AppKit, using ImageIO, PDFKit, and AVFoundation. Everything happens on your Mac.

## Try it

Build the app with Xcode 16 or newer and macOS 14 or newer:

```sh
./Scripts/build.sh
open dist/Fold.app
```

The generated app is at `dist/Fold.app`. Move it to `/Applications` and open it once to make Finder Services discoverable. This development build is ad-hoc signed; public distribution requires a Developer ID certificate and notarization. Build on an Intel Mac for an Intel executable; the current local build is for Apple Silicon.

## Designed around Finder

- **Control–Option–Space** reads your selected files in Finder and opens a small floating panel. It uses an independent queue, so earlier workspace files aren’t accidentally converted.
- **Finder → right-click → Services** provides “Convert with Fold,” “Merge PDFs with Fold,” and “Edit PDF Pages with Fold.” If missing, enable them in System Settings → Keyboard → Keyboard Shortcuts → Services. Services registration can require logging out and back in after installation.
- The shortcut’s first use prompts for permission to control Finder. It only reads the current selection, on demand. Services and drag-and-drop work without that permission.
- The menu-bar icon keeps Fold available after closing its window. Quit with Command–Q.
- In Fold’s **Merge PDFs** workspace, drop another PDF on a document to choose before/after. Drag queued PDFs to reorder, or use the move controls. Finder itself doesn’t expose a supported PDF-on-PDF drop interception API.

The integration uses [macOS Services](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html) and an on-demand Finder Apple event. [Finder Sync](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) is designed around managed directories, badges, and contextual menus; Fold doesn’t patch Finder or intercept its normal file operations.

## What works

| Task | Capabilities |
| --- | --- |
| Images | HEIC/HEIF, PNG, JPEG, TIFF, BMP, and other still images supported by ImageIO → PNG, JPEG, HEIC, TIFF, or a single-page PDF |
| Video | MP4, MOV, M4V; macOS-native fallback when FFmpeg is unavailable |
| Extended video | With FFmpeg: additional input containers such as MKV, WebM, AVI; output MP4, MOV, M4V, WebM, MKV; audio extraction to M4A or MP3 |
| Audio | M4A; with FFmpeg, MP3 and WAV |
| Merge PDFs | Document previews, reorder, reverse, before/after drop insertion, filename and destination choices |
| PDF pages | Thumbnails, reorder, rotate, remove, undo, select ranges, extract selected pages, save an edited copy |

Images are decoded at their original pixel dimensions with orientation applied. Transparent JPEG exports use white backgrounds. PNG and TIFF are lossless; the quality setting applies to lossy formats. Metadata such as GPS/EXIF is not copied. Animated or multipage images are rejected explicitly rather than silently flattened.

FFmpeg is optional. Fold checks `Contents/Helpers/ffmpeg`, `/opt/homebrew/bin/ffmpeg`, and `/usr/local/bin/ffmpeg`. A standard Homebrew installation (`brew install ffmpeg`) enables the additional formats. No FFmpeg binary is redistributed in this repository. Bundle a properly licensed build and its dependencies before distributing a self-contained app with those extra formats. Extended conversion uses H.264/AAC or VP9/Opus; it doesn’t preserve every auxiliary track, HDR metadata, or subtitles. Native video support depends on the codecs macOS can read.

Password-locked PDFs must be unlocked in Preview first. PDFs that disallow page copying are rejected. PDF edits make a new document; digital signatures and document-level interactive structures such as bookmarks and forms aren’t guaranteed to survive page assembly.

## File safety and responsiveness

- Originals are read-only inputs. Files are staged next to the destination, then moved into place only after successful export.
- Existing files are never replaced. A duplicate name becomes `Photo 2.png`, `Photo 3.png`, and so on. A concurrent filename collision fails safely.
- Export cancellation stops the video encoder and removes unfinished staging files; completed batch outputs remain available.
- Conversion and PDF work run away from the UI thread. Video exports report actual progress.
- Recent exports are stored locally in `~/Library/Application Support/Fold/History.json`. Clearing history doesn’t delete exported files.
- System, Light, and Dark appearances; native open panels, SF Symbols, keyboard shortcuts, and accessibility labels.

## Development

```sh
swift build
swift test
./Scripts/build.sh debug
```

The tests create their own files and cover HEIC orientation, transparency, image-to-PDF, animated image rejection, PDF ordering and rotations, range parsing, locked PDFs, source preservation, output collisions, playable video, M4V audio, native AVFoundation export, and cancellation. HEIC encoding and native video tests need macOS image/video services; a restricted process environment can block those hardware-backed services.

Create optional sample documents and images:

```sh
swift Scripts/make-samples.swift TestResults/Samples
```

Regenerate the icon:

```sh
swift Scripts/make-icon.swift .cache/Fold.iconset
iconutil -c icns .cache/Fold.iconset -o Resources/Fold.icns
```

`Sources/FoldCore` contains the conversion and PDF logic. `Sources/Fold` contains the app, Finder integration, queues, and interface. The project has no third-party Swift dependencies and can be opened directly via `Package.swift` in Xcode.
