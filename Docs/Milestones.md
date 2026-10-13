# Coreplay milestones

| # | Milestone | Status |
| --- | --- | --- |
| 1 | Foundation: project, packages, design system, VLCKit, basic player on iPhone and Mac | Built (not yet compiled in Xcode) |
| 2 | Engine: protocol, both engines, router, events, tracks and subtitles, Now Playing, remote commands, background audio | Built (not yet compiled in Xcode) |
| 3 | Library v1: sources, scanning, music tags and artwork, Music section, mini player, Now Playing | Next |
| 4 | Video library: filename parsing, TMDB, Movies and TV, detail pages, resume, Continue Watching | |
| 5 | Video player polish: scrub thumbnails, every Level 2 option, PiP, AirPlay, macOS menus and shortcuts | |
| 6 | VLC parity: feature checklist against the sample suite | |
| 7 | Network: SMB, UPnP, FTP/SFTP, NFS, streams, Chromecast | |
| 8 | Extras: queue polish, smart playlists, lyrics, equalizer, sleep timer, iCloud sync, widgets, App Intents, Handoff | |
| 9 | Hardening: accessibility, performance, tests, soak testing | |

---

## Milestones 1 and 2 — October 13, 2026

### What was built

**Project**
- One multiplatform SwiftUI target (iOS/iPadOS 26 and native macOS 26, not Catalyst), Swift 6 language mode.
- Folder-synchronized groups for `App/Coreplay` and `App/Platform`, seven local packages, and a shared scheme whose test action runs the package tests.
- `Config/Base.xcconfig` for team, bundle ID prefix and version.
- `Info.plist` with:
  - viewer document types for video, audio and disc images;
  - imported type declarations for MKV, WebM, FLV, Ogg, Opus, FLAC, WMV, WMA and others;
  - background audio;
  - Files sharing and open-in-place;
  - the `coreplay://open?url=…` scheme;
  - an App Transport Security exception for media;
  - a local-network usage description.
- macOS sandbox entitlements.
- App icon and in-app logo built from the supplied artwork (`Design/Coreplay-logo-source.png`), plus an accent colour taken from the cone's orange.

**PlaybackEngine** (the only code that imports VLCKit)
- **PlaybackCore** (Foundation only), containing:
  - the `PlaybackEngine` protocol and `AsyncStream<PlaybackEvent>`;
  - state, tracks, chapters, metadata and capabilities;
  - the pure `EngineRouter` with codec allowlists;
  - mapping from settings to libVLC options;
  - time formatting.
- **VLCKitEngine** on the official VLCKit 4.0.0a25 binary, consumed through SwiftPM with a pinned URL and checksum.
  - Delegate callbacks from libVLC threads are bridged into the stream.
  - End of media is detected correctly for libVLC 4.
  - Stops are serialized.
  - VLC never gets the chance to open its own window.
- **AVPlayerEngine** for natively supported media, with:
  - media-selection tracks;
  - chapters;
  - common metadata;
  - AirPlay video.
- **MediaProber**, an actor that inspects every track with AVFoundation and gives up after 3 s.
- **PlaybackController**, which:
  - routes each item;
  - mirrors state for SwiftUI;
  - serializes engine switches;
  - hands playback to VLC at the same position. This happens for subtitle or audio timing, external subtitles and speeds above 2×, keeping speed, volume and track languages, and also when AVFoundation fails.
  - manages security-scoped file access.
- **VideoSurface**: one long-lived video view that each player screen borrows, so reopening the player never rebuilds VLC's video output.

**NowPlaying**
- `PlaybackQueue` with Apple Music's Up Next, shuffle and repeat behaviour.
- `PlaybackSession`, which ties together the engine, the queue and system integration.
- `MPNowPlayingInfoCenter`, including artwork and the macOS playback state.
- Remote commands: play, pause, toggle, stop, next and previous; ±15 s skip for video; scrubbing; rate.
- `AVAudioSession` handling: playback category, interruptions with resume, and pausing when headphones are unplugged.
- Video pauses when the app goes to the background.

**DesignSystem**
- Palette, brand assets, metrics, and motion presets that respect Reduce Motion.
- An artwork view that decodes off the main thread.
- An Apple Music-style animated mesh background sampled from the artwork.
- A scrubber that VoiceOver can adjust and that gives haptics on iPhone.
- Transport buttons with symbol effects.
- Empty states.

**Features**
- **Home**: the current item with its progress, plus Open Files.
- **Library and Search**: structure, scopes and empty states.
- **Player**:
  - a video player whose overlay hides itself, with skip ±10 s, a resolution badge, AirPlay, and speed and audio/subtitle menus;
  - Playback Options covering tracks, speed up to 4×, subtitle and audio timing, chapters, engine switching and media info;
  - the audio Now Playing screen, with a compact layout for short windows;
  - Up Next, with reordering, swipe to remove and history;
  - the iOS mini player in the tab bar's bottom accessory;
  - the Mac playback bar.
- **Settings**: hardware decoding, stream buffer, Always Use VLC Engine, custom libVLC options, and About with the LGPL licence and source offer.

**App**
- **iPhone and iPad**:
  - a tab bar that becomes a sidebar on iPad;
  - the mini player, with a zoom transition into the full-screen player;
  - the Files picker that accepts any file, and "Open in…";
  - the screen stays on while video plays.
- **Mac**:
  - a sidebar main window with the playback bar;
  - a separate video window with full screen, F and Esc;
  - File and Playback menus;
  - opening files from Finder and the Dock, and drag and drop.

### How it was checked
I couldn't run Xcode here, so verification happened outside it:

- **Unit tests on Linux.** The Foundation-only code (PlaybackCore and the queue) compiles with Swift 6.2 in Swift 6 mode, and 50 Swift Testing tests pass. They cover routing, containers, FourCC codes, option parsing, track naming and language matching, time formatting and queue behaviour.
- **VLCKit API names.** The real VLCKit 4.0.0a25 headers were imported through Clang. Every VLCKit call, and the Swift names of every delegate method, type-checks.
- **Concurrency checking.** The engine and NowPlaying sources were compiled with Swift 6 concurrency checking against stand-ins for Apple's frameworks, with no errors or warnings.
- **Race reproductions.** Reproductions of the engine-switching and VLC stop/end-of-media races pass after the fixes. A random-timing stress test ran 0 failures in 150 runs.
- **Project files.** The project file was parsed and every object reference resolves. Info.plist, the entitlements and the scheme are valid.

**Not done:** a real Xcode build, or running on a simulator or device. Expect to fix a few compile errors on the first build; send them over and I'll fix them.

### Stubbed or deferred
- **Placeholder packages:** MediaLibrary, MetadataProviders and Networking are placeholders. Library tabs and search results show empty states until Milestones 3 and 4.
- **Engine preference:** the per-item engine preference exists on `PlaybackItem` but isn't stored yet, because there is no library. Switching engines from Playback Options lasts for the current item only.
- **Later milestones:**
  - Picture in Picture, scrub thumbnails, landscape-first video on iPhone, aspect ratio, crop, deinterlacing, equalizer and snapshots (5–6);
  - Chromecast and network browsing (7);
  - sleep timer, lyrics, smart playlists, iCloud sync, widgets, App Intents, Handoff and CarPlay (8).
- **Remote commands:** like and dislike wait for ratings in the library.

### Where this deviates from the build prompt, and why
1. **Engines run on the main actor, not their own actors.** VLCKit and AVKit drive their players and video views from the main thread, and VLCKit already moves libVLC work onto its own queue. Our own expensive work (probing, and later scanning and thumbnails) runs in actors.
2. **Settings live in `UserDefaults` (`AppSettings`), not SwiftData.** They move with the library and sync milestones. The keys are stable, so values can be migrated.
3. **iPad multiple windows are switched off for now.** Player presentation is app-wide, so a second window would present the player twice. This returns with per-scene state in Milestone 5.
4. **The Mac menu's Play/Pause has no Space shortcut.** The player and main window handle Space themselves, so typing in text fields keeps working.
5. **Some Level 2 controls arrived early.** Subtitle and audio timing, plus chapters, are in Playback Options already, because they exercise the engine hand-off.
6. **Feature modules have a `Feature` suffix** (`HomeFeature`, `PlayerFeature`…). This avoids generic module names such as `Library` or `Settings`.
7. **VLCKit 4 is still an alpha (4.0.0a25).** It was chosen as agreed. It's pinned in `Packages/PlaybackEngine/Package.swift`; moving to a newer build means changing the URL and checksum.
8. **The logo is a set of exported bitmaps, not drawn in code.** The app icon and in-app logo are generated from your artwork with `Tools/make_brand_assets.py`.

### Before any public release
- The supplied logo combines Apple's logo and VLC's cone. That's fine for a personal build. Apple's trademark guidelines don't allow the Apple logo in third-party app icons (App Review rejects it), and the cone is a VideoLAN trademark, so the icon needs replacing before distribution.
- The prompt's licensing points still apply: VLCKit stays dynamically linked and unmodified, the Acknowledgements screen stays, check codec patents, and get legal advice.

### First build checklist
1. Open `Coreplay.xcodeproj` in Xcode 26 or later.
2. Set `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`, or choose a team under Signing & Capabilities.
3. Let Swift Package Manager download VLCKit. It's large.
4. Build the **Coreplay** scheme for **My Mac**, then for an iPhone simulator.
5. If anything fails, copy the first errors from the Issue navigator (⌘5) and send them over.
