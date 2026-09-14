# XAssistant Mac

[简体中文](README.md) | English

A local macOS keyboard and mouse activity tracker with animated 3D heatmap video exports.

Adapted from the functionality and ideas of [xuhk/XAssistant](https://github.com/xuhk/XAssistant), reimplemented natively in Swift. This is an unofficial macOS version; no upstream Windows source code or assets were copied, and this project is not affiliated with the original author. Licensed under the [MIT License](LICENSE).

## Features

- Track keyboard and mouse activity in the background from the menu bar, with daily statistics and keyboard heatmaps.
- Detect built-in and external keyboards, with MacBook and full-size Mac layouts and manual selection.
- Select a start and end time, with Earliest and Now shortcuts.
- Export animated presses and cumulative heatmaps to Downloads as 1080p, 30 fps MP4 videos, automatically compressing idle gaps.
- Include or exclude mouse clicks; choose speeds from 0.5× to 256×, including 128×.
- Scale heatmap colors dynamically against the current highest cumulative press count, or use the final highest count in the selected range as a fixed maximum.
- Hold the final heatmap for five seconds while the camera slowly rotates.
- Play a synchronized sound for every press, with a distinct timbre per physical key and keyboard, mechanical, soft, or silent presets.

## Install

Requires **Apple Silicon and macOS 13 or later**. Xcode is not needed for a downloaded build.

- **Download:** Open the [latest release](https://github.com/nope-gao/XAssistant-Mac/releases/latest), download `XAssistant-Mac-arm64.zip`, unzip it, and move **XAssistant Mac.app** to `~/Applications`.
- **Terminal install / update:** Quit the running app first, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

The installer downloads the latest release, verifies its SHA-256 checksum, and installs it to `~/Applications` without sudo. Existing recordings are preserved. These methods require a published release with the app ZIP attached; GitHub's automatic Source code ZIP is not the app.

Current builds are ad-hoc signed and not notarized by Apple. If macOS blocks the app, review its source and use **System Settings → Privacy & Security → Open Anyway**. Then enable Input Monitoring as described below.

## Interface language

The initial setting is **Follow system**. The app checks the ordered macOS preferred-language list and selects a supported match. Available languages: **简体中文, 繁體中文, English, 日本語, Español, Français, Deutsch**. English is used if none of your preferred languages are supported. Choose a language or return to Follow system at the bottom of the window; the preference is saved.

The interface, menus, existing status messages, dates and numbers, mouse labels, function-key names, and video captions follow the selected language. Letter keys retain the physical ANSI layout. Videos keep the language selected when the export starts; manual switching is disabled during export. macOS controls the language of its own permission dialogs and underlying system error details.

## Video sound

Choose **Keyboard taps** (default), **Mechanical**, **Soft taps**, or **Silent**. Each physical key has a distinct, deterministic short timbre, triggered only on key down and aligned to the first animation frame showing the press. Dense presses overlap at higher speeds. Excluding the mouse also excludes its click sounds. The five-second outro remains quiet.

Audio is synthesized locally. It does not use the microphone, record your real keyboard, or depend on external sound assets. Sound-enabled videos contain a 48 kHz AAC track; Silent exports have no audio track.

## Build from source

Requires Xcode Command Line Tools. The build script produces an ARM64 app only; compatibility has not been verified across all supported macOS versions.

```bash
# Run once if developer tools are not installed
xcode-select --install

# Build from the project directory, including signature checks and self-tests
bash build.sh

# Install to a stable location and launch
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

The current version uses local ad-hoc signing, not Apple Developer ID signing or notarization.

## Usage and permissions

After first launch, open **System Settings → Privacy & Security → Input Monitoring** and enable **XAssistant Mac** from its installed location. Quit and reopen the app. Use your keyboard and mouse, then confirm that the latest recording time and counts actually update before exporting.

Rebuilding or replacing the app may invalidate an existing permission. If access is enabled but no activity is recorded, quit the app and run:

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

Then add the installed app to Input Monitoring again, enable access, and relaunch. This resets Input Monitoring permission only for this app.

Choose the time range, speed, mouse option, and heatmap mode, then click **Export to Downloads**. Activity from periods without recordings cannot be recovered.

## Local data and privacy

Data is stored in `~/Library/Application Support/XAssistantMac/`. The app does not upload it or include telemetry. The installer accesses GitHub to download releases.

Animated playback requires press/release timestamps, physical key identifiers, device information, and event order. The app also stores application names, bundle IDs, and usage-duration statistics. It does not read final text produced by an input method, window titles, web addresses, or mouse coordinates. **Key identifiers and their sequence may still reveal what was typed. Recordings are sensitive data; do not publicly upload the data directory.**

## Known limitations

- Primarily supports ANSI layouts. ISO/JIS layouts are not fully supported; automatic detection may not cover every third-party device.
- Fn keys, media keys, and secure input may not be fully recorded. Touch ID is not an ordinary recorded key press.
- Device attribution may be limited when multiple keyboards are used. Holding a key does not count automatic repeats as separate presses.
- Videos use SceneKit, Metal, and AVFoundation directly; Blender is not required.

## Publish an update (maintainers)

Update the version and build number in `build.sh`, commit the changes, and push a matching tag:

```bash
git tag v0.4.0
git push origin main --tags
```

Pushes to main build and verify translations, press timing, and actual audio/video encoding. Version tags publish a release after these checks pass with the app ZIP and checksum file. Use a new version for each subsequent release. Alternatively, run `bash package.sh` and manually attach `dist/XAssistant-Mac-arm64.zip` and `dist/SHA256SUMS` to the matching GitHub release.
