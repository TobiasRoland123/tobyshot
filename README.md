# TobyShot

A native macOS capture app built with Swift, AppKit, SwiftUI, ScreenCaptureKit, and Vision. No web view, Electron runtime, third-party dependencies, account, or cloud service.

## Run

Requires macOS 15 or newer and the Swift toolchain from Xcode or Command Line Tools.

```sh
bash scripts/run.sh
```

This builds and opens `build/TobyShot.app`. You can also open that app directly in Finder. For a release build:

```sh
bash scripts/build.sh release
```

The build uses a persistent self-signed code-signing identity stored in the ignored, private `.local-signing` directory so local rebuilds keep the same app identity. Set `TOBYSHOT_SIGNING_IDENTITY` to use an existing Apple signing identity. Distribution to other Macs will require Developer ID signing and notarization. The build script selects the complete macOS 26.5 SDK when the preview macOS 27 Command Line Tools are missing their SwiftUI macro plugin; `TOBYSHOT_SDK` can override the choice.

The first local build creates the certificate and stops until you approve its code-signing trust. To approve that certificate for code signing in your user account, run the following from the project directory, then build again. This does not add TLS trust or change screen recording permissions. Keep `.local-signing` across rebuilds; do not commit or share its private keychain and password.

```sh
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$PWD/.local-signing/tobyshot-signing.keychain-db" \
  "$PWD/.local-signing/certificate.pem"
```

For an explicitly temporary ad-hoc build, use `TOBYSHOT_SIGNING_IDENTITY=- bash scripts/build.sh release`. Its screen recording grant may need refreshing whenever the binary changes.

Use **Check access** in the library or make a capture attempt to check screen recording access. If capture fails even though TobyShot is enabled under **System Settings → Privacy & Security → Screen & System Audio Recording**, quit TobyShot, remove only its existing entry with the minus button, then use plus to add the current `build/TobyShot.app` from Finder and reopen it. Avoid resetting privacy settings for other apps. Opened images and the built-in sample canvas work without screen recording access. Microphone permission is requested only when microphone recording is enabled.

## Included in 0.1

- Native capture library with search, image import, clipboard paste, drag-out files, and local history.
- Area, full-screen, window, and timed screenshots. Full-screen capture follows the display under the pointer; area/window selection supports all connected displays.
- A floating Quick Access preview with save, copy, annotate, pin, recognize text, and reveal in Finder.
- Annotation tools: arrows, rectangles, filled rectangles, ellipses, lines, freehand, text, numbered steps, opaque redaction, pixelation, crop, move/delete, undo/redo, zoom, and backgrounds.
- Annotation appearance: bundled Excalifont and classic Virgil text fonts, plus clean, sketch, and hand-drawn arrows, rectangles, filled rectangles, ellipses, lines, and numbered circles. Outlines support solid, dashed, or dotted strokes.
- Automatic canvas expansion: draw, type, or move annotations beyond any image edge; saved and copied images include the full content, including strokes and shadows. Background padding surrounds the expanded canvas.
- MP4 screen or area recording with optional system audio and microphone, 15/30/60 fps, resolution limits, countdown, and stop controls.
- Text recognition on the Mac with automatic, English, and Danish language selection.
- Persistent settings for export, post-capture actions, preview behavior, image output, recording, annotation, file naming, clipboard, retention, backgrounds, and pinned images.
- Customizable global shortcuts, a menu bar launcher, and launch-at-login support.

| Action | Default shortcut |
| --- | --- |
| All-in-One capture launcher | Command Shift 5 |
| Capture area | Command Shift 4 |
| Capture fullscreen | Command Shift 3 |
| Capture window / record screen / open file | Unassigned |
| Open from clipboard / resume saved annotation | Command Shift V |
| Save and close / Save as (editor) | Command S / Command Shift S |
| Copy object / screenshot (editor) | Command C / Command Shift C |
| Duplicate object / Print (editor) | Command D / Command P |
| Move / Crop / Draw | V / K / D |
| Arrow / Text / Counter | A / T / C |
| Ellipse / Line / Redaction | E / L / P |
| Rectangle / Filled rectangle / Background | R / F / B |
| Increase / decrease tool size | Apostrophe / Plus |
| Pixelate (TobyShot extra) | X |
| Settings | Command , |

**Settings → Shortcuts** follows CleanShot’s categories and supports search, recording, clearing, and restoring defaults. Capture, OCR, overlay, pin, history, and image-opening actions work globally. Annotation actions and single-letter tool keys work only in the active editor. Save shortcuts also work while typing an annotation; tool shortcuts leave text input alone, and editor shortcuts leave sheets alone. All-in-One opens a compact chooser for area, fullscreen, window, or recording.

**Command S** saves and closes the annotation window after a successful export. **Command Shift V** reopens that same session with editable annotations, canvas settings, and undo/redo history while TobyShot remains running and the clipboard is unchanged. Copying a new image starts a new annotation session. **Save as…** keeps the editor open; cancelled or failed saves also keep it open.

Defaults match the supplied CleanShot references for supported features. Open From Clipboard retains Command Shift V to honor the earlier Command preference, instead of the reference’s Control A. Unsupported cloud, scrolling-capture, video-editor, and additional annotation-tool shortcuts are not presented as working controls. Existing custom shortcuts and cleared assignments survive upgrades; saved values matching the old five defaults migrate once to the new defaults.

Click a shortcut and press the new combination; Escape cancels and Delete clears. Changes apply immediately and survive relaunch. **Restore Defaults** removes your overrides. Conflicts with TobyShot, macOS, and other apps leave the previous assignment intact. To resolve macOS screenshot conflicts, choose another combination or reassign the system keys under **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**. TobyShot does not change system shortcuts.

Right-click a library capture for export, OCR, pinning, Finder, and history actions. Closing the library leaves TobyShot running in the menu bar; quit from the application or menu bar menu.

**Settings → Annotate → Appearance** previews and saves the text font, **Shape style**, and **Shape stroke** defaults. Your existing arrow style now applies to other geometric shapes too. Defaults apply to new annotations, including in already-open editors. Existing annotations retain their style when resized, moved, duplicated, undone, or exported. Use the editor’s color and size controls to change the selected annotations. Freehand follows your drawn path, while redaction and pixelation keep their full rectangular coverage. The fonts work offline and their licenses and sources are bundled in `Sources/TobyShot/Resources/Fonts`.

After drawing, placing a numbered step, applying a crop, or finishing text entry, TobyShot switches to the pointer (Move) tool. New annotations stay selected. Tool buttons are clickable across their full area, including the space around each icon.

Annotation edits automatically update the clipboard with the latest full image. This includes live text, completed drawing and resize gestures, appearance and background changes, crops, and undo/redo. Automatic copies respect **Settings → Advanced → Copy format** and do not add captures to history or show copy notifications. Selection, zoom, and tool changes leave the clipboard alone.

Hold Shift while drawing to snap lines and arrows to 45° increments, make rectangles and filled rectangles square, or make ellipses circular. Press or release Shift at any point during the drag to switch between constrained and free drawing.

With the pointer (Move) tool, drag from empty canvas space to select annotations inside or touching the selection box. Drag any selected annotation to move the group. Delete, Duplicate, and Copy object apply to the entire selection. Shift-drag adds to the selection; Shift-click toggles an annotation. Click empty space or press Escape to clear the selection.

For arrows, drag either round endpoint handle to reposition the start or tip, drag the middle handle to bend the arrow, or drag the arrow itself to move it. Double-click the middle handle to straighten it. Select an existing arrow with Move to adjust it again. Curves work with every arrow style and stroke, and are preserved when moving, duplicating, cropping, copying, or exporting. Each adjustment is one undo step.

Select any placed shape with Move to edit it. Drag a corner handle to resize rectangles, filled rectangles, ellipses, freehand drawings, numbered steps, redactions, or pixelation regions. Drag either endpoint to adjust a line. Numbered steps stay round. Drag the shape itself to move it. Color and size changes apply to the selected annotations; size also controls text size, numbered-step size, and pixelation strength. Redactions remain opaque black. Each resize or appearance change can be undone.

## Local files

Exports default to `~/Pictures/TobyShot`. The app keeps a separate history copy under `~/Library/Application Support/TobyShot/Captures`. **Settings → Screenshots → Automatic deletion** offers **Off**, **10**, **30**, **90**, and **120 days**. It is off by default. When enabled, screenshots reaching the selected age are permanently deleted from the library along with their saved export files, including multiple exports of the same screenshot. Cleanup runs at launch, when the app becomes active, when the setting changes, and hourly while TobyShot is running. Moved or renamed exports cannot be located automatically. Manually removing a library item still preserves its exported files.

Recording history retains its existing seven-day default, configurable in **Settings → Advanced → Recording history**; expiring recordings preserves their exported files. Turn off automatic Save to keep captures only in local history until you export them. PNG history copies preserve original image quality; export supports PNG, JPEG, and TIFF.

## Scope of this first version

This is a working first release rather than full CleanShot feature parity. Cloud sharing, scrolling capture, video trimming, GIF export, keystroke and click overlays, automatic Do Not Disturb, URL automation, custom wallpaper images, and crosshair magnification are not implemented. Related planned features are identified in settings where applicable. The built-in background styles are generated gradients. Recording currently caps the longest edge at 4096 pixels for H.264 compatibility. The annotation editor exports flattened images, not editable project documents.

## Development

```sh
bash scripts/test.sh
```

The tests cover file naming and collision avoidance, Retina selection coordinates, recording dimensions, image formats, redaction, background dimensions, crop orientation and undo, history persistence, and shortcut defaults, migration, persistence, conflicts, native registration, editor scope, and suspension during editing. Screen capture/recording additionally requires an interactive Mac session and OS permission.

Open `Package.swift` in Xcode if preferred. The app bundle is assembled by `scripts/build.sh`, so full Xcode is not required for a local build. `--demo` opens the sample annotation canvas, and `--settings` opens settings at launch.

## Structure

- `TobyShotApp.swift`: application lifecycle, windows, menus, and shortcuts.
- `AppCoordinator.swift`: capture, export, annotation, recording, and OCR workflows.
- `ScreenCaptureService.swift` / `RegionSelector.swift`: native capture and selection.
- `CaptureStore.swift`: local history, image conversion, clipboard, and output.
- `AnnotationEditor.swift` / `AnnotationCanvas.swift`: annotation model, renderer, and editor.
- `SettingsView.swift` / `ShortcutSettingsView.swift`: preferences and shortcut recording.
- `ShortcutAction.swift` / `Shortcut.swift` / `HotKeyManager.swift`: shortcut catalog, persistence, validation, and global registration.
- `CaptureLauncher.swift`: All-in-One capture chooser.
- `LibraryView.swift` / `FloatingViews.swift`: library, sample canvas, previews, pins, and recording controls.

The app icon uses the Dark Glass capture design in `Resources/Branding/tobyshot-dark-glass-app-icon.png`. Its opaque artwork fills the square canvas so macOS can mask it without adding an outer glass tile. `scripts/build-icon.sh` generates its standard and Retina `.icns` representations during each app build. The library and settings display the same bundled icon. The original transparent logo remains in `Resources/Branding/tobyshot-dark-glass-primary.png`. The menu bar uses a monochrome version from `Resources/Branding/tobyshot-dark-glass-menubar.png`, packaged at 18 and 36 pixels as a template image that adapts to the menu bar appearance.
