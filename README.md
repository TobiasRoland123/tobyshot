# TobyShot

A native macOS capture app built with Swift, AppKit, SwiftUI, ScreenCaptureKit, and Vision. Captures stay on your Mac. Sparkle handles signed app updates from GitHub; no account is needed to use the app.

## Install and update

Download `TobyShot-<version>.dmg` from [TobyShot's GitHub Releases](https://github.com/TobiasRoland123/tobyshot/releases), open it, and drag **TobyShot** into **Applications**. Requires macOS 15 or newer; release builds support both Apple silicon and Intel. The ZIP download contains the same app.

Use **Check for Updates…** in TobyShot's menu bar menu, application menu, or **Settings → About → Updates**. Automatic checks are enabled by default and can be switched off there. When an update is available, Sparkle downloads it, verifies its signature, and replaces the installed app when you approve the update and restart. Settings, exports, and capture history remain in their existing locations. Finish captures or recordings before updating; the existing quit checks also protect unsaved annotation edits.

An older build without the updater needs one initial replacement: quit TobyShot and copy the new app into Applications, replacing the old app. You do not need to uninstall or delete your data. Subsequent versions can update inside the app.

The public `TobiasRoland123/tobyshot` repository hosts both the source and downloadable releases. Downloads become available once the first release is published. The app fetches updates without a GitHub login and never embeds a GitHub token.

## Publish a release

The release workflow creates a **draft** in this repository with a universal DMG, ZIP, signed `appcast.xml`, and SHA256 checksums. Publish the draft after reviewing it; ensure it is marked **Latest**. The installed app fetches `https://github.com/TobiasRoland123/tobyshot/releases/latest/download/appcast.xml`, and that feed points at the version's ZIP. GitHub Actions uses its built-in `GITHUB_TOKEN` to upload releases; no extra repository or personal access token is needed.

One-time setup:

1. Run `bash scripts/setup-updates.sh` on the Mac that will own update signing. It creates or reuses the `app.tobyshot.mac` Sparkle key in the login Keychain and adds only its public key to `Resources/Info.plist`. This checkout already has its public key configured. On another Mac, import the original private key instead of generating a replacement. Back up that key securely; existing apps trust it for future updates.
2. Add the `SPARKLE_PRIVATE_KEY` Actions secret in this repository. You can export the existing key into an ignored private file and pipe it directly to GitHub, without printing it:

   ```sh
   mkdir -p .local-signing
   (umask 077; .build/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account app.tobyshot.mac -x .local-signing/sparkle-private-key)
   gh secret set SPARKLE_PRIVATE_KEY --repo TobiasRoland123/tobyshot < .local-signing/sparkle-private-key
   ```

   Store any backup privately and remove the exported file when done. Never commit or upload the key as a release asset.
3. For normal macOS installation without Gatekeeper's unidentified-developer prompt, configure Developer ID signing and notarization using these Actions secrets: `APPLE_CERTIFICATE_P12_BASE64` (exported Developer ID Application certificate and private key), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_PASSWORD` (app-specific password), and `APPLE_TEAM_ID`. Keep the same app identifier and Developer ID identity across releases to preserve macOS permissions. Without Apple credentials, CI produces an ad-hoc signed build: macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt, and screen recording permission may need refreshing after updates.

Once the changes are in GitHub, run **Actions → Release → Run workflow** with a version such as `0.2.0`, or push a matching version tag such as `v0.2.0`. Every release must have a higher numeric **build number** (`CFBundleVersion`) than previous releases. CI defaults to its run number plus two; if you override it, keep later builds above your override. Version numbers (`CFBundleShortVersionString`) appear in the UI. Published release assets are never replaced by CI.

To prepare the same files locally without publishing:

```sh
bash scripts/release.sh 0.2.0 3
```

Output is in `build/release/`. Local builds retain the existing self-signed development identity unless `TOBYSHOT_SIGNING_IDENTITY` is set. For a Developer ID release, also set `TOBYSHOT_DISTRIBUTION=1`; optionally set `TOBYSHOT_NOTARY_KEYCHAIN_PROFILE` to a stored `notarytool` credential profile. To sign updates with a securely stored private key file instead of the Keychain, set `TOBYSHOT_SPARKLE_PRIVATE_KEY_FILE`. Keep that file outside tracked source. `TOBYSHOT_ARCHS` can override the release default of `arm64 x86_64`.

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

Annotation edits automatically update the clipboard with the latest full image. This includes live text, completed drawing and resize gestures, appearance and background changes, crops, and undo/redo. Full-resolution rendering and image encoding happen when another app requests the clipboard contents, keeping typing responsive on large screenshots. Automatic copies respect **Settings → Advanced → Copy format** and do not add captures to history or show copy notifications. Selection, zoom, and tool changes leave the clipboard alone.

The editor draws shapes and text as vector overlays so they stay crisp when zooming. It caches the screenshot preview at the display resolution and reuses pixelation patches while other objects move. Saved and copied images retain the full output resolution.

Hold Shift while drawing to snap lines and arrows to 45° increments, make rectangles and filled rectangles square, or make ellipses circular. Press or release Shift at any point during the drag to switch between constrained and free drawing.

With the pointer (Move) tool, drag from empty canvas space to select annotations inside or touching the selection box. Drag any selected annotation to move the group. Delete, Duplicate, and Copy object apply to the entire selection. Shift-drag adds to the selection; Shift-click toggles an annotation. Click empty space or press Escape to clear the selection.

For arrows, drag either round endpoint handle to reposition the start or tip, drag the middle handle to bend the arrow, or drag the arrow itself to move it. Double-click the middle handle to straighten it. Select an existing arrow with Move to adjust it again. Curves work with every arrow style and stroke, and are preserved when moving, duplicating, cropping, copying, or exporting. Each adjustment is one undo step.

Select any placed shape with Move to edit it. Drag a corner handle to resize rectangles, filled rectangles, ellipses, freehand drawings, numbered steps, redactions, or pixelation regions. Drag either endpoint to adjust a line. Numbered steps stay round. Drag the shape itself to move it. Color and size changes apply to the selected annotations; size also controls text size, numbered-step size, and pixelation strength. TobyShot remembers the last text size set with the size control or text corner handles for new text, including in later screenshots and after restarting; existing text keeps its own size. Redactions remain opaque black. Each resize or appearance change can be undone.

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
- `AppUpdater.swift`: Sparkle update checks, settings, and menu integration.
- `AppCoordinator.swift`: capture, export, annotation, recording, and OCR workflows.
- `ScreenCaptureService.swift` / `RegionSelector.swift`: native capture and selection.
- `CaptureStore.swift`: local history, image conversion, clipboard, and output.
- `AnnotationEditor.swift` / `AnnotationCanvas.swift`: annotation model, renderer, and editor.
- `SettingsView.swift` / `ShortcutSettingsView.swift`: preferences and shortcut recording.
- `ShortcutAction.swift` / `Shortcut.swift` / `HotKeyManager.swift`: shortcut catalog, persistence, validation, and global registration.
- `CaptureLauncher.swift`: All-in-One capture chooser.
- `LibraryView.swift` / `FloatingViews.swift`: library, sample canvas, previews, pins, and recording controls.

The app icon uses the Dark Glass capture design in `Resources/Branding/tobyshot-dark-glass-app-icon.png`. Its opaque artwork fills the square canvas so macOS can mask it without adding an outer glass tile. `scripts/build-icon.sh` generates its standard and Retina `.icns` representations during each app build. The library and settings display the same bundled icon. The original transparent logo remains in `Resources/Branding/tobyshot-dark-glass-primary.png`. The menu bar uses a monochrome version from `Resources/Branding/tobyshot-dark-glass-menubar.png`, packaged at 18 and 36 pixels as a template image that adapts to the menu bar appearance.
