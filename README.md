# TobyShot

A free macOS app for screenshots, screen recordings, annotations, and text recognition. Captures stay on your Mac. Requires **macOS 15 or newer**, on Apple silicon or Intel.

## Install

**We don't have a paid Apple Developer membership.** TobyShot is self-signed and isn't notarized by Apple, so macOS may block it on first launch. Follow the steps below if you trust this repository and your download hasn't been modified.

1. Download `TobyShot-<version>.dmg` from **Assets** on the [latest release](https://github.com/TobiasRoland123/tobyshot/releases/latest). You don't need the **Source code** downloads.
2. Quit TobyShot if it's already running. Open the DMG and drag **TobyShot.app** into **Applications**, replacing the old copy if you're upgrading.
3. Eject the DMG and open **TobyShot** from **Applications**.
4. If macOS says the developer can't be verified or Apple can't check the app for malicious software, dismiss the warning. Go to **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** for TobyShot.
5. Confirm **Open** and follow any macOS confirmation prompts. Future launches should open normally.

These steps follow [Apple's guidance](https://support.apple.com/en-us/102445). Keep Gatekeeper enabled. If the warning says the app is damaged, contains malware, or will damage your computer, stop and contact the developer.

### Finish setup

On first launch, TobyShot opens a short setup checklist. Its default shortcuts (⌘⇧3, ⌘⇧4, and ⌘⇧5) match the built-in macOS screenshot shortcuts, which take priority until you turn them off. Setup lists only the shortcuts that conflict, including customized ones, and checks again when you come back from System Settings.

1. Turn off the listed shortcuts in **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**, or choose different TobyShot shortcuts.
2. Allow screen capture as described below.
3. Choose the folder where TobyShot saves your screenshots and recordings, or keep `~/Documents/Captures`. macOS may ask you to allow TobyShot to access your Documents folder.
4. Take a test screenshot, then click **Finish Setup**.

You can skip setup and reopen it later from **Settings → General → Setup**.

### Allow screen capture

1. Click **Allow Access** in setup, or **Check access** or **Capture area** in TobyShot.
2. Enable **TobyShot** in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen the app.
3. Click **Capture area** and drag to select a region.

Microphone permission is only needed when you enable microphone audio for recordings.

If capture still fails, quit TobyShot, remove only its entry from **Screen & System Audio Recording**, add the current **Applications → TobyShot.app** with **+**, and reopen it.

## Features

- Capture an area across multiple monitors, a window, or a full screen, with an optional timer.
- In Capture Area, hover over bordered containers, scroll through enclosing areas, then click to capture. Drag for a custom rectangle.
- Annotate, crop, redact, copy, save, or pin screenshots.
- Paste screenshots into the annotation canvas with ⌘V, then move and resize them to make insets or side-by-side comparisons.
- Keep recent captures stacked in Quick Access, and drag any of them into another app.
- Record your screen with optional system audio and microphone.
- Recognize text, search local capture history by title or by the text inside screenshots, and customize shortcuts.
- Open the latest screenshot in Codex with a configurable global shortcut.

Exports go to `~/Documents/Captures` by default. If you used an earlier version that saved to `~/Pictures/TobyShot`, TobyShot keeps using that folder until you choose another one. Closing the library keeps TobyShot running in the menu bar.

To use Codex, assign **Open Latest Screenshot in Codex** under **Settings → Shortcuts → General**. It starts unassigned and can be changed or disabled there. The action opens the latest screenshot from history, skipping newer recordings, in a new Codex composer for you to add a prompt and send. You can also run it from TobyShot’s menu bar menu. This requires a Codex Desktop version that supports opening image files.

## Updates

Choose **Check for Updates…** from the menu bar or **Settings → About → Updates**. Older versions without the updater can be replaced using the installation steps above. Your settings and capture history are kept.

## Development

Requires the Swift toolchain from Xcode or Command Line Tools. From the project directory:

```sh
bash scripts/run.sh
```

The first build creates a local signing certificate and stops until you trust it for code signing. Run this once, then rerun `scripts/run.sh`:

```sh
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$PWD/.local-signing/tobyshot-signing.keychain-db" \
  "$PWD/.local-signing/certificate.pem"
```

Keep `.local-signing` across rebuilds so the app keeps its identity. Never commit its private keys or passwords.

```sh
bash scripts/test.sh          # Run tests
bash scripts/build.sh release # Build build/TobyShot.app
```

### Area suggestions prototype

Capture Area detects bordered or distinctly filled boxes on-device from the frozen screen images, after the selector is usable. A click allows 4 points of movement; dragging farther starts a manual rectangle at the press point. Scrolling selects an enclosing or enclosed area and centers the pointer. The original nesting path stays selected until the pointer leaves it. Trackpad motion accumulates over 24 points, with at least 150 ms between steps; momentum is ignored. Recording and dedicated window capture use their existing selectors.

Open `Resources/FeatureMocks/area-suggestions.html` in a browser at 1100 × 850 to try the nested charts, controls, rounded borders, shadows, clipping, and occlusion cases. Its light and dark versions produced the four containers plus four smaller controls in browser-image checks. The negative examples retained the three visible containers and a button, and omitted the clipped and obscured parents. The detector uses a reduced contour proposal image with full-resolution boundary validation to keep suggestions responsive. The app logs readiness and candidate count under subsystem `TobyShot`, category `AreaSuggestions`.

This is a feasibility prototype, not a semantic UI classifier. It accepts complete borders or sharp filled silhouettes, including smaller cards, chat bubbles, buttons, input boxes, and short prompt chips of at least 64 × 14 points. Continuous separators and background changes also identify pane sections using visible window bounds; sections can share edges with their enclosing pane. Rounded corners and faint borders are supported; unbounded text, tiny icons, extremely faint or thick boundaries, and pixel contours touching display edges may be missed. Fully visible window geometry can supply those edges for separated panes. The same frozen pixels are used to refine and crop every candidate. Pixel evidence and window ordering reject uncertain visibility, but cannot prove arbitrary in-page occlusion or identify every clipped element. Content grouped only by meaning, without a visible boundary or separator, is not independently inferred. Manual dragging remains available for these cases.

Before treating the interaction as release-ready, try a mouse wheel and trackpad (including momentum and path endpoints), and physically arranged displays above, below, and left of the main screen at mixed scales. Check pointer recentering, Escape, Capture Previous Area, and the configured copy/save/annotate/pin actions with the fixture. Automated tests cover selection state, event routing, pixel crops, visibility, and coordinate conversion; they do not establish how recentering feels on hardware.
