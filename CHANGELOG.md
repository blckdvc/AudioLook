# Changelog

All notable changes to **AudioLook**.

## 1.4.2 — 2026-11-25
- **Type the root note.** The list of 128 notes is replaced by a small field: type a note name
  (`C3`, `f#2`, `Bb1`) or a MIDI number (`60`) and press Return. Without an octave (`F#`), octave 3
  is used; an entry that can't be read leaves the root unchanged.
- With the cursor in that field, the key you play on the MIDI keyboard becomes the root note.

## 1.4.1 — 2026-11-25
- **The playhead follows the note you play.** While a MIDI note sounds, the playhead and the time
  counter track that note through the A/B region, at the speed of the note (twice as fast an
  octave up). With several notes held it follows the last one played; when the notes stop it goes
  back to the transport position.

## 1.4.0 — 2026-11-25
- **Play the sample from a MIDI keyboard.** AudioLook works as a classic sampler: the **root
  note** (C3 by default) plays the A/B region as you hear it, and the other notes play it higher
  and faster or lower and slower.
  - Two modes: **Play once** or **Loop A/B while held**. Releasing the key stops the sound.
  - Up to 16 notes at once, velocity, pitch bend (±2 semitones) and sustain pedal.
  - Listens to every connected MIDI device, and adds a MIDI port called **“AudioLook”** that a
    track in Logic (or any DAW) can play.
  - A new **MIDI keyboard** row in the window; a played note stops the loop playback.

## 1.3.0 — 2026-11-16
- **Automatic updates** — AudioLook checks GitHub for a new release at launch and then once a
  day. When one is available it shows the release notes and offers **Install and Relaunch**,
  **Later** or **Skip This Version**. The new version is downloaded, verified (SHA-256 when
  published, same app, newer version, intact signature), installed in place and relaunched.
- Menu-bar entries **Check for Updates…** and **Check Automatically** (on by default).
- **Renamed audiolook → AudioLook**, in the app, the disk image and the repository.
- **New bundle identifier**, `com.blckdvc.AudioLook`. macOS treats it as a new app: the window
  goes back to its default place once, and the permission to read the Finder selection is
  asked again. Earlier versions do not update themselves: install this one once from the DMG.
- **Fix** — opening a file through a symbolic link now selects that file instead of the first
  one in its folder.
- A silent **demo mode** (`-demoData YES`) for screenshots, and `NOINSTALL=1 ./build.sh` to
  build without installing.

## 1.2.2 — 2026-10-27
- **Piano keyboard in the piano-roll** — a vertical keyboard on the left (black / white keys)
  with shaded black-note lanes and an octave line at each C, so pitches are easy to read.

## 1.2.1 — 2026-10-27
- **MIDI volume** — the **Volume** control now works for `.mid` files too (it sets the MIDI
  Channel Volume, so it changes the level without affecting the timbre).

## 1.2.0 — 2026-10-27
- **MIDI playback** — load Standard MIDI Files (`.mid` / `.midi`) and audition them with
  Apple's built-in **General MIDI** sound bank. The waveform area turns into a **piano-roll**;
  A/B loop, tempo, transpose, zoom / pan, magnetic grid and the space bar all work as with audio.
- **Transpose & tempo on MIDI** — the Pitch control shifts the notes, the tempo re-times
  playback (both non-destructive).
- **Drag a MIDI region into your DAW** — dragging the piano-roll exports a `.mid` of the A/B
  region (with your transposition applied), ready to drop onto a track and play with your own
  instruments.

## 1.1.3 — 2026-10-24
- **Aligned controls** — Volume / Pitch (and Tempo / Grid) now sit on shared,
  aligned columns (icon · label · slider · value · reset) instead of drifting with
  each label's width. Stays compact (two columns).
- **Finer magnetic grid** — added **1/32, 1/64, 1/128** divisions.

## 1.1.2 — 2026-10-24
- **Much sharper waveform** — redrawn as a smooth, anti-aliased **min/max envelope**
  at up to ~1 point per sample (capped), so it stays crisp when zoomed.
- **Space bar** toggles play/pause once the player has keyboard focus (click the
  window). The player follows the Finder **without stealing focus**, so arrow-key
  browsing in the Finder keeps working.
- Removed the inoperative **⌘Q** shortcut shown next to "Quit" in the menu.

## 1.1.0 — 2026-10-24
- **Waveform zoom** — mouse wheel or trackpad pinch; **pan** with a two-finger
  horizontal scroll or **Shift + wheel** (zoom and pan around the cursor).
- **Higher-resolution waveform** — detail scales with the file length, so zooming in
  stays sharp instead of blocky.
- **Export by dragging the waveform** straight into any DAW (or the Finder). The
  exported WAV (24-bit) carries the applied **pitch and tempo** (unless Bypass is
  on). The separate drag chip and the **Render** button were removed.
- **Automatic A/B-region export** — when the loop isn't the whole file, only the
  segment between the A and B markers is exported (no checkbox); the bounds follow
  the markers shown on the waveform.
- **More precise BPM detection** — sub-lag (parabolic) interpolation removes the
  ~1 BPM rounding bias.
- **Two-column layout** (Volume / Pitch · Tempo / Grid) with a cleaner footer.
- **Window size and position remembered** between launches.
- **Tempo resets to each sample's own detected BPM** (no longer carried over).
- **Space bar** toggles play / pause.
- **Attack preserved** at the loop start (the first kick stays punchy).
- **About** window now shows a clickable **"buy me tokens"** badge (→ PayPal).
- Interface **follows the system language** (English / French).
- Wider A/B handle grab zone.

## 1.0 — 2026-10
- Renamed **LoopLook → audiolook**, new Finder-inspired icon.
- **BPM** detection and tempo matching (replacing the old "%").
- **Magnetic grid** (1/16, 1/8, 1/4, bar) and a **move bar** to slide the A/B region.
- **Click-free** playback (crossfades); playback stops when the window is closed.
- Adjustable window transparency, hidden title bar, keyboard-editable values.
- Export: drag-and-drop the processed WAV (24-bit) into any DAW.

## 0.1
- Initial release (as **LoopLook**): floating / menu-bar audio loop player with
  A/B looping and high-quality time-stretch / transposition (Signalsmith Stretch).

---

## Support the project
Free and open-source 🙂 — if you feel like it, buy me a few tokens:

[![Buy me tokens](https://raw.githubusercontent.com/blckdvc/AudioLook/main/docs/buy-me-tokens.png)](https://paypal.me/lbenh)
