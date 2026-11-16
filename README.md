# AudioLook

A macOS **audio loop** player in a floating / menu-bar window, with **high-quality**
time-stretch and transposition (Signalsmith Stretch engine, offline rendering).
Made to audition and prepare samples before dragging them into a DAW.

The interface follows the system language (English, or French on a French macOS).
See the [changelog](CHANGELOG.md) for what's new.

![AudioLook — main window](docs/screenshot-main.jpg)
![AudioLook — A/B loop region](docs/screenshot-loop-ab.jpg)

### Support the project
Free and open-source 🙂 — if you feel like it, buy me a few tokens:

[![Buy me tokens](docs/buy-me-tokens.png)](https://paypal.me/lbenh)

## Features

- **MIDI playback**: load a Standard MIDI File (`.mid` / `.midi`) and audition it with Apple's
  built-in General MIDI sound bank. The display becomes a **piano-roll** and every control below
  (loop, tempo, transpose, zoom/pan, grid, space bar) works the same way. Dragging the piano-roll
  exports a **`.mid`** of the A/B region (with your transposition) to drop into your DAW.
- **Waveform** with playhead; click to seek. **Zoom** with the mouse wheel or a trackpad pinch;
  **pan** with a two-finger horizontal scroll (trackpad) or **Shift + wheel** (mouse).
- **A/B loop** with crossfade (click-free): two handles, or the **bar at the top between
  A and B** to slide the whole region (freely, or snapped to the grid).
- **Tempo (BPM)**: automatic detection + match to a target BPM (pitch unchanged).
  Source BPM is editable, or enter the number of beats.
- **Transposition** −24…+24 semitones (tempo unchanged).
- **Magnetic grid** (1/16, 1/8, 1/4, bar) derived from the BPM.
- **Attack preserved** at the loop start (no fade over the first transient — the kick stays punchy).
- **Volume**, adjustable window **transparency**, values editable from the keyboard.
- **Bypass processing** to compare with the original.
- **Follow the Finder selection**: selecting an audio file opens and plays it automatically;
  a non-audio selection stops playback. Playback also stops when the window is closed.
- **Export**: **drag the waveform** straight into any DAW (or the Finder) — drop it exactly
  where you want it in the arrangement. The exported WAV (24-bit) includes the applied pitch and
  tempo, and, if the A/B loop isn't the whole file, contains only the segment between the markers.
- Settings **kept from one file to the next** (volume / pitch / bypass). The tempo resets to
  each sample's own detected BPM.

### In pictures

![AudioLook — a loop with its waveform and playhead](docs/screenshot-waveform.png)

![AudioLook — an A/B region dragged over one bar of the loop](docs/screenshot-loop.png)

![AudioLook — the same loop matched to 140 BPM and transposed by three semitones](docs/screenshot-tempo.png)

![AudioLook — a MIDI file shown as a piano-roll, with its keyboard gutter](docs/screenshot-midi.png)

![AudioLook — an A/B region on the piano-roll](docs/screenshot-midi-loop.png)

![AudioLook — the interface in French, following the system language](docs/screenshot-french.png)

## Install (DMG)

Download [`AudioLook.dmg`](AudioLook.dmg), open it and drag **AudioLook** into **Applications**.

The app is **ad-hoc signed** (no paid Apple Developer account), so on **first launch**:
right-click **AudioLook › Open › Open** (macOS 13/14), or System Settings › Privacy & Security ›
**“Open Anyway”** (macOS 15). A short “Read me” is included in the DMG.

AudioLook lives in the **menu bar** (no Dock icon): select an audio file in the Finder and it
opens on its own.

## Updates

From version 1.3.0, AudioLook updates itself: it checks the
[GitHub releases](https://github.com/blckdvc/AudioLook/releases) at launch and once a day, and
offers to install a new version (downloaded, verified, installed in place, relaunched).
Use **Check for Updates…** in the menu-bar menu to check now, or untick **Check Automatically**
to turn it off. Versions before 1.3.0 need to be updated once by hand from the DMG.

![AudioLook — a new version is available, with its release notes](docs/screenshot-update.png)

For the update to install, AudioLook must be in a folder it can write to (e.g. **Applications**),
not launched straight from the DMG.

The download is checked against the SHA-256 published with the release, and the app inside
must be AudioLook, newer, with an intact signature. The app is ad hoc signed, not notarized:
that check proves the download is the one published on GitHub, not who built it.

**Publishing a release** (maintainer): bump the version in `build.sh`, add a section to
`CHANGELOG.md`, then run `./release.command` — it builds, makes the DMG and its SHA-256,
commits the DMG, pushes and creates the GitHub release that the app looks for.

## Export to a DAW

- **Drag the waveform**: just drag the waveform itself into your DAW's arrangement and drop it
  where you want (the playhead position, for instance) — works with any DAW. A single **click**
  on the waveform still moves the playhead; the A/B handles and the top bar keep their own drags.
- **Processing included**: the exported WAV reflects the current pitch and tempo (unless
  **Bypass** is on, which exports the original).
- **A/B region**: when the A/B loop is *not* the whole file, only the segment between the A and B
  markers is exported. Click **Whole loop** to reset A/B and export the whole file.
- To **save** the file instead of dropping it in a DAW, just drag it into a Finder window or onto
  the Desktop.

## Build (without Xcode)

The **Command Line Tools** are enough:

```bash
./build.sh
```

The script compiles the C++ bridge (Signalsmith) with `clang++`, then the app with `swiftc`,
ad-hoc signs it and installs it to `~/Applications/AudioLook.app`.
`DEVELOPER_DIR` is forced to the Command Line Tools (avoids the Xcode license).

To build the DMG: `./makedmg.command` (produces `AudioLook.dmg`).

### Demo mode

`NOINSTALL=1 ./build.sh` builds and signs the app without installing or launching it.

Launched with `-demoData YES`, the app opens synthesized loops instead of following the Finder selection, and stays silent: this is how the screenshots above are made. `-demoStage midi` opens the MIDI file, `-demoStage update` shows the update window without installing anything, `-demoLoopA 0.25 -demoLoopB 0.5` sets the A/B region, `-demoTargetBPM 140` the target tempo and `-demoTranspose 3` the transposition.

## Architecture

```
Src/
  main.swift                app (menu-bar agent)
  AppDelegate.swift         global shortcut, Finder-selection follow, window
  PlayerViewController.swift UI (waveform, controls, export)
  LoopPlayer.swift          A/B loop playback, fades, re-render
  SampleProcessor.swift     file read + Signalsmith render + WAV export
  BPMDetector.swift         tempo detection (RMS envelope + autocorrelation)
  WaveformView.swift        waveform + A/B handles + magnetic grid
  WaveformAnalyzer.swift    peak/RMS computation
  LogicImporter.swift       temp WAV export for drag-and-drop / render
  Localize.swift            tiny EN/FR localization helper
  StretchBridge.{h,cpp}     C bridge to Signalsmith Stretch
  Bridging.h                Swift/C bridging header
Vendor/                     Signalsmith Stretch + Linear (headers)
```

## Licenses

Third-party code in `Vendor/` (see `LICENSE-THIRD-PARTY.md`):
- [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch) — MIT
- [Signalsmith Linear](https://github.com/Signalsmith-Audio/linear) — MIT
