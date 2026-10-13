# Coreplay: Build Prompt for a VLC-Powered Media Player on iOS & macOS

Oct 13, 2026 · @Manish Jangid

## Role and mission

You are a senior Apple-platform engineer and product designer. You will build Coreplay, a personal media player for iOS/iPadOS and macOS that plays anything VLC can play, but feels like Apple Music and the Apple TV app.

The product in one sentence: **VLC's engine, Apple's experience, the user's own library.** Every file the user owns (movies, TV episodes, music, podcasts, home videos) is scanned, enriched with metadata and artwork, and presented in a browsable, beautiful library. Playback must handle every container, codec and subtitle format VLC supports, with no transcoding.

Principles that override everything else:

- **It plays everything.** If VLC desktop can open it, this app can open it.
- **It never looks like VLC.** No settings-heavy dialogs, no exposed jargon in the main UI. Power features live one level down, in places Apple would put them.
- **Same experience on every device.** Phone, iPad and Mac share one design language, one data model and one feature set, adapted to each platform's conventions rather than identical pixel-for-pixel.
- **Native first.** Use SwiftUI and Apple frameworks wherever they exist. Reach for VLCKit only for what Apple's stack cannot do.

## Platforms, stack and project structure

Build one multiplatform SwiftUI app targeting iOS/iPadOS and native macOS (not Mac Catalyst). Use Swift 6 strict concurrency from day one.

| Layer | Choice | Notes |
| --- | --- | --- |
| Language | Swift 6 | Strict concurrency; `@MainActor` for UI, actors for engine and library work |
| UI | SwiftUI | AppKit/UIKit only via representables where SwiftUI falls short (video surface, some menus) |
| State | Observation (`@Observable`) | No Combine-heavy architecture |
| Persistence | SwiftData | Library, playback progress, playlists, settings |
| Sync | CloudKit via SwiftData | Progress, playlists, ratings; never media files |
| Primary engine | VLCKit | Prefer VLCKit 4 ([NEWS](https://code.videolan.org/videolan/VLCKit/-/raw/master/NEWS)): unified framework for all Apple platforms, PiP on iOS and macOS, dual subtitles, new track API. Fall back to 3.6.x (MobileVLCKit + VLCKit) if 4.x is not stable enough when you start |
| Secondary engine | AVFoundation (AVPlayer) | For natively supported files: better battery, HDR, AirPlay video |
| Dependency manager | Swift Package Manager | Use a maintained VLCKit SPM wrapper, or vend the official XCFramework yourself |
| Tests | Swift Testing + XCUITest |  |

Modularise as local Swift packages so the UI never talks to VLCKit directly. That keeps the engine swappable and makes a future Android/Windows port a matter of reimplementing packages, not untangling them.

```
App/
  Coreplay/             # app entry, scenes, windows, commands
  Platform/iOS/         # iOS-only views, gestures
  Platform/macOS/       # menus, toolbars, multi-window, Dock menu
Packages/
  PlaybackEngine/       # protocol + VLCKitEngine + AVPlayerEngine + EngineRouter
  MediaLibrary/         # scanning, indexing, metadata, artwork, SwiftData models
  MetadataProviders/    # TMDB, MusicBrainz, Cover Art Archive, embedded tags
  NowPlaying/           # MPNowPlayingInfoCenter, remote commands, queue
  Networking/           # SMB, UPnP/DLNA, FTP/SFTP, WebDAV, streams
  DesignSystem/         # colours, typography, components, motion
  Features/             # Home, Library, Search, Player, Settings (one module each)
```

## Design guidelines

Follow Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) for iOS, iPadOS and macOS, and use the current Apple Music and Apple TV apps as the reference for every screen. When the HIG and VLC's conventions disagree, the HIG wins.

### Foundations

- **Use the system design language.** Adopt the current OS material and glass treatment, system tab bars, sidebars and toolbars. Never draw custom chrome that imitates them.
- **Typography.** SF Pro via semantic text styles (`.largeTitle`, `.title2`, `.headline`, `.body`, `.caption`) so Dynamic Type works everywhere. Bold large titles on browse screens, like Apple Music.
- **Colour.** System semantic colours plus one accent colour. In Now Playing and detail pages, derive the background from the artwork (dominant colour extraction, blurred and darkened artwork, or an animated mesh gradient as Apple Music does).
- **Light and dark mode** both fully supported. Video playback and Now Playing are always dark.
- **SF Symbols** for every icon, with symbol effects (bounce, replace, variable colour) for state changes like play/pause.
- **Motion.** Spring animations, `matchedGeometryEffect` and zoom navigation transitions from artwork into detail and into the player. Respect Reduce Motion.
- **Artwork is the interface.** Large, rounded-corner artwork with subtle shadows. Square for audio, 2:3 posters and 16:9 stills for video. Never show a filename where a title and artwork could be.
- **Haptics** on iPhone for scrubbing detents, play/pause and long-press menus.

### Navigation

|  | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Top level | Tab bar: Home, Music, Videos, Library, Search | Sidebar-adaptable tab view | Sidebar (`NavigationSplitView`) with sections: Home, Music (Artists, Albums, Songs, Genres, Playlists), Videos (Movies, TV Shows, Home Videos), Sources, Playlists |
| Mini-player | Floating bar above the tab bar (tab view bottom accessory) | Same | Playback bar across the top or bottom of the window, like Music on macOS |
| Full player | Expands from the mini-player with a drag-to-dismiss sheet | Same, larger artwork | Separate resizable window or full-screen; supports multiple windows |
| Video | Full-screen, landscape-first, auto-rotate | Full-screen or PiP | Own window, native full-screen, PiP, floating on top option |
| Input | Touch and gestures | Touch, pointer, keyboard | Keyboard shortcuts, menu bar commands, media keys, trackpad gestures |

### Screens to build, modelled on Apple's apps

1. **Home** (Apple TV "Watch Now" + Apple Music "Listen Now"): Continue Watching row with progress bars, Up Next for TV episodes, Recently Added, Recently Played music, auto-generated rows ("Unwatched Movies", "Albums you haven't played in a while").
2. **Music library:** Artists, Albums, Songs, Genres, Composers, Playlists. Album grid; album detail with large artwork, track list, disc grouping and shuffle/play buttons.
3. **Now Playing (audio):** full-bleed artwork-derived background, large artwork that shrinks when paused, scrubber with elapsed and remaining time, volume, synced lyrics view, queue view (Up Next, history, shuffle, repeat), AirPlay route picker.
4. **Movies and TV:** poster grids, a hero detail page with backdrop, logo or title, synopsis, cast, runtime, audio/subtitle availability badges (4K, HDR, Dolby Vision, Atmos, 5.1). TV shows group by season with episode stills and watched state.
5. **Video player:** chrome-free by default; tap to reveal a minimal overlay with title, scrubber with thumbnail previews, play/pause, ±10s skip, and an "info" panel for audio tracks, subtitles, playback speed and advanced options. Auto-hides after 3 seconds.
6. **Search:** one search across everything, results grouped by type, with recent searches and tokens/scopes.
7. **Sources:** local folders, Files, network shares and streams, styled like a settings list, not a file browser.
8. **Settings:** native `Form` on iOS and a `Settings` scene with tabs on macOS.

### Hiding VLC's power without losing it

Every VLC option must be reachable, but layered. Level 1 is what Apple shows (play, scrub, tracks, AirPlay). Level 2 sits behind an info button or context menu (subtitle delay, audio delay, speed, aspect ratio, equalizer, chapters). Level 3 lives in an Advanced section of Settings (deinterlacing modes, network caching, hardware decoding toggles, raw libVLC options). Use plain-language labels, e.g. "Subtitle timing" rather than "SPU delay".

## Playback engine: using VLCKit for full VLC coverage

Wrap all playback behind one protocol, route each item to the best engine, and expose every libVLC capability through that protocol. Do not fork VLC; link VLCKit as a library. Verify every API name below against the VLCKit version you install, since 3.x and 4.x differ.

### Architecture

1. **`PlaybackEngine` protocol** with `load`, `play`, `pause`, `seek(to:)`, `rate`, `volume`, track listing and selection, subtitle and audio delays, video adjustments, snapshot, and an `AsyncStream<PlaybackEvent>` for state, time, buffering, tracks-changed, errors and end-of-media.
2. **`VLCKitEngine`** built on `VLCMediaPlayer`, `VLCMedia`, `VLCMediaList` and `VLCLibrary`. Map `VLCMediaPlayerDelegate` callbacks into the event stream. Keep all player calls on one actor or the main thread.
3. **`AVPlayerEngine`** built on `AVPlayer`/`AVQueuePlayer` for files Apple can play natively.
4. **`EngineRouter`** decides per item. Use AVPlayer when the container, video, audio and subtitle formats are all natively supported (e.g. MP4/MOV with H.264/HEVC/AAC, or MP3/AAC/ALAC/FLAC music). Use VLCKit for everything else (MKV, AVI, WMV, FLV, OGG, Opus in MKV, DTS, TrueHD, AC-3 in MKV, ASS/PGS subtitles, network protocols, discs). If the user picks a track or feature mid-playback that AVPlayer cannot do, hand off to VLCKit at the same timestamp without visible interruption. Add a per-item and a global "Always use VLC engine" override.
5. **Video surface:** a `UIViewRepresentable` / `NSViewRepresentable` whose view is set as the player's `drawable`. Never let VLC create its own window.
6. **Options:** global libVLC options go into `VLCLibrary(options:)`; per-item options via `VLCMedia.addOption`. Surface the important ones in Settings and keep a raw "Custom libVLC options" field in Advanced.

### Feature coverage checklist

Implement every row. Where the API is uncertain, check the VLCKit headers (4.x also exposes the full libVLC C API).

| Area | VLC feature | VLCKit route | Where it appears |
| --- | --- | --- | --- |
| Formats | All containers and codecs VLC ships, 4K/8K, 10-bit, HDR10, HLG, Dolby Vision tone-mapping | Built in | Automatic; show format badges in info panel |
| Decoding | Hardware decoding via VideoToolbox, software fallback | Library option for the codec module | Advanced: "Hardware decoding" toggle |
| Audio tracks | Select track, audio delay, stereo/mono/left/right modes, downmix | Track selection API, audio delay property, stereo mode | Player info panel → Audio |
| Audio processing | 10-band equalizer with presets and preamp, volume normalisation, ReplayGain, volume boost above 100% | Equalizer API (`VLCAudioEqualizer` in 4.x), audio filter options | Now Playing → Equalizer sheet; Settings → Audio |
| Speed | 0.25×–4× with pitch preservation | `rate` | Player menu; long-press on the speed button |
| Subtitles | Embedded and external SRT, ASS/SSA (full styling), WebVTT, TTML, VobSub, PGS, DVB, CEA-608/708 | Track API; `addPlaybackSlave` for external files | Info panel → Subtitles |
| Subtitle control | Delay, size, font, colour, outline, background, position, text encoding, two simultaneous tracks (4.x) | Subtitle delay property; freetype/text renderer options | Info panel → Subtitles → Style and timing |
| Subtitle search | Find subtitles online | OpenSubtitles REST API (your code, not VLC) | "Search subtitles" in the subtitle menu |
| Video | Aspect ratio, crop, fill/fit/zoom, rotate, flip, deinterlace modes, brightness/contrast/saturation/hue/gamma | Aspect ratio and crop properties, deinterlace filter, adjust filter | Info panel → Video; pinch-to-zoom on iOS |
| 360° video | Pan around spherical video | Viewpoint API | Drag gesture on the video surface |
| Navigation | Chapters, titles, DVD/Blu-ray menus, frame-by-frame, jump to time, A–B loop | Chapter/title APIs, next-frame call, time property (A–B loop in your code if unavailable) | Scrubber chapter ticks; info panel; keyboard shortcuts |
| Snapshots | Save the current frame | Snapshot API | Player menu; saved to Photos or a folder |
| Discs and images | DVD and Blu-ray ISO/folders (unencrypted), VIDEO\_TS | Open as media URL | Sources; macOS also physical drives |
| Network streams | HTTP(S), HLS, DASH, RTSP, RTP/UDP multicast, RTMP, MMS | Open as media URL; network caching option | "Open Network Stream" in Sources and the File menu |
| Network shares | SMB 1/2/3, FTP, SFTP, NFS, UPnP/DLNA, Bonjour discovery | `VLCMediaDiscoverer` for discovery; credentials via VLC's dialog provider | Sources |
| Playlists | M3U, M3U8, PLS, XSPF, CUE sheets | `VLCMediaList` parsing | Import into the library as playlists |
| Casting | Chromecast | `VLCRendererDiscoverer` and renderer items | Route picker next to AirPlay |
| Visualisations | Spectrum and other audio visualisers | Audio visual option | Optional Now Playing mode |
| Media info | Codec, bitrate, resolution, frame rate, channels, sample rate | `VLCMedia` parsing and track info | "Media Info" sheet |
| Recording and conversion | Record a stream, convert files | libVLC record/stream output via the C API | Later milestone, Mac first |

Build a **parity test suite**: a folder of sample files covering each row, played through both VLC desktop and this app, with the results logged. A feature is done only when it matches VLC.

## Media library

The library is what makes this feel like Apple Music and Apple TV, so treat it as a first-class product, not a file browser. First evaluate VideoLAN's `VLCMediaLibraryKit` (the indexer behind VLC for iOS). If its Swift ergonomics or SwiftData integration are poor, build your own indexer on SwiftData.

### Sources

- The app's own Documents folder, exposed in the Files app ("On My iPhone") and via Finder file sharing.
- User-picked folders anywhere (iCloud Drive, external drives, other apps' folders), stored as security-scoped bookmarks so access survives relaunch.
- On macOS: Music and Movies folders, external and network volumes, plus drag-and-drop of files or folders onto the window or Dock icon.
- Network shares (SMB, UPnP, FTP/SFTP, NFS): browsable always, optionally indexed into the library.
- Single files opened via "Open in…", share sheet, Finder double-click or URL scheme play immediately and can be added to the library.

### Scanning

- Incremental scans keyed on path, size and modification date; never re-parse unchanged files.
- Watch for changes with FSEvents on macOS; rescan on foreground and on a background task on iOS.
- Run scanning in a background actor with progress shown in the UI. Never block launch.
- Missing files are marked unavailable (e.g. drive unplugged), not deleted, so play history survives.

### Classification and metadata

| Media | How to classify | Metadata sources, in priority order |
| --- | --- | --- |
| Music | Audio UTType | Embedded tags (ID3, Vorbis comments, MP4 atoms, APE) → folder artwork (`cover.jpg`, `folder.jpg`) → optional MusicBrainz + Cover Art Archive lookup |
| Lyrics | Track sidecar | Embedded lyrics → `.lrc` sidecar (synced) → optional LRCLIB lookup |
| Movies | Video with a title and year pattern, or in a Movies source | Local `.nfo`, `poster.jpg`, `fanart.jpg` → TMDB (user supplies their own API key) |
| TV episodes | `S01E02`, `1x02` patterns or `Show/Season 1/` folders | Local `.nfo` → TMDB TV (series, season and episode artwork, titles, air dates) |
| Home videos | Anything else | Creation date, location from file metadata, generated thumbnail |

Always offer **"Fix match"** and **"Edit info"** so the user can correct titles, artwork and grouping. Manual edits are never overwritten by a rescan.

### Data model (SwiftData)

`MediaFile` (bookmark, path, size, hash, duration, container, track info, engine preference) is the physical file. On top of it sit `Track`, `Album`, `Artist`, `Genre`, `Movie`, `TVShow`, `Season`, `Episode`, `HomeVideo` and `Playlist` (manual and smart). `PlaybackState` stores position, play count, last played, rating and favourite. `Source` stores folders and shares.

### Artwork and thumbnails

- Disk cache with several size variants (thumbnail, grid, hero), decoded off the main thread.
- Generate video thumbnails with `VLCMediaThumbnailer` or AVFoundation when no artwork exists.
- Generate scrub-preview sprite sheets in the background for long videos.

### Progress rules

Resume when position is past 1 minute and before 92%. Past 92% or into the end credits, mark watched and advance Up Next to the next episode. Music counts as played after 50% or 4 minutes.

## System integration

These make the app feel like it belongs on the device. Each one works the same regardless of which engine is playing.

- **Now Playing and remote commands:** `MPNowPlayingInfoCenter` (title, artist, album, artwork, duration, elapsed time, rate) and `MPRemoteCommandCenter` (play/pause, next/previous, skip ±15s for video and podcasts, change position, like/dislike). Drives the Lock Screen, Control Center, Dynamic Island, AirPods, CarPlay, the Mac menu bar Now Playing widget and media keys.
- **Background audio:** `AVAudioSession` category `.playback`, background mode enabled, interruption handling (calls, Siri, other apps), route-change handling (pause when headphones are unplugged).
- **AirPlay:** `AVRoutePickerView` in Now Playing and the video player. Audio routes through the system for both engines. For video on AirPlay, prefer AVPlayer; for VLC-only formats, use external-display output as VLC for iOS does.
- **Picture in Picture:** `AVPictureInPictureController` for AVPlayer; VLCKit 4's PiP support for the VLC engine. Auto-enter PiP when the app backgrounds during video.
- **Live Activity** on iPhone for current playback (optional, Dynamic Island already covers basics via Now Playing).
- **Widgets:** Continue Watching and Recently Played widgets on iOS home screen and macOS desktop, plus a Control Center control for play/pause.
- **App Intents and Siri:** "Play \[album\] in Coreplay", "Resume \[show\]", "Shuffle my library"; Shortcuts actions for the same; Spotlight indexing of library items.
- **Files and Finder:** register as a viewer for all media UTTypes; "Open in" and share-sheet import; Quick Look-style preview on macOS where possible.
- **CarPlay** audio app template (requires Apple's CarPlay entitlement; keep it as a later milestone).
- **Handoff:** start a video on the iPhone, continue at the same position on the Mac via `NSUserActivity`.
- **Display:** HDR and EDR output on supported screens, frame-rate matching where available, keep the screen awake during video (`isIdleTimerDisabled` on iOS, power assertion on macOS).
- **macOS specifics:** full menu bar (File, Edit, Playback, Audio, Video, Subtitles, Window), keyboard shortcuts matching VLC and QuickTime conventions (Space, ←/→, ⌘←/→, F for full-screen, ⌘↑/↓ volume), multiple player windows, "Float on top", Dock menu with playback controls, media keys.

## Other features

### Queue and playlists

- Up Next queue with Play Next, Play Later, drag to reorder, swipe to remove, history of what played.
- Shuffle and repeat (one, all) with Apple Music's behaviour; Autoplay continues with similar items when the queue ends.
- Gapless playback for albums (use `AVQueuePlayer` when supported, VLC's media list otherwise) and optional crossfade (implement in your audio layer if the engine lacks it).
- Manual playlists and smart playlists (rules on genre, rating, play count, date added, unwatched), plus import and export of M3U and XSPF.
- Ratings, favourites and "Loved" tracks feeding Home rows.

### Playback conveniences

- Sleep timer (minutes, end of track, end of episode).
- Skip intro and credits markers (manual per show, remembered).
- Per-file memory of audio track, subtitle track, delays, aspect ratio and speed; per-show defaults for preferred audio and subtitle languages.
- Default language preferences in Settings (e.g. "Audio: Japanese, Subtitles: English").
- Podcasts and audiobooks treated as spoken word: remember position, ±15/30s skip, chapter support for M4B.

### Sync and privacy

- CloudKit syncs library metadata, progress, playlists, ratings and settings between the iPhone and the Mac. Media files are never uploaded.
- If a file is on one device only, show it on the other as unavailable, or play it from a network share if one is configured.
- No analytics or third-party SDKs. All metadata lookups are opt-in and use the user's own API keys.

### Security and access

- Optional Face ID / Touch ID lock and hidden folders for private content.
- Credentials for network shares stored in the Keychain.

### Settings (grouped as Apple would)

General, Library and Sources, Playback, Audio (equalizer, normalisation, ReplayGain), Video (deinterlacing, hardware decoding), Subtitles (style, encoding, default languages), Network (caching, timeouts), Metadata (TMDB key, MusicBrainz, LRCLIB), Privacy and Lock, and Advanced (engine override, raw libVLC options, logs).

## Quality, accessibility and licensing

### Accessibility

- VoiceOver labels and actions on every control, including custom scrubbers (adjustable trait) and artwork grids.
- Dynamic Type up to accessibility sizes without truncating titles in player controls.
- Full keyboard navigation and Full Keyboard Access on both platforms.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast and Bold Text.
- Subtitle styling honours the system "Subtitles & Captioning" preferences by default, and SDH/CC tracks are labelled.

### Performance targets

| Metric | Target |
| --- | --- |
| Cold launch to interactive library | Under 1 s with 10,000 items |
| Tap play to first frame (local file) | Under 300 ms |
| Grid scrolling | Steady 120 Hz on ProMotion devices |
| Library size | 50,000 tracks and 5,000 videos without slowdown |
| Memory during 4K playback | Under 400 MB |

Use lazy grids, paged SwiftData fetches, off-main-thread image decoding and Instruments profiling before each milestone ends.

### Testing

- Unit tests for the filename parser, engine router, metadata matching and progress rules (Swift Testing).
- Engine contract tests run against both `VLCKitEngine` and `AVPlayerEngine`.
- The VLC parity sample suite from the playback section, run on device.
- UI tests for the core flows: import, browse, play, mini-player expand, track switching, resume.

### Licensing and distribution

- VLCKit and libVLC are LGPL 2.1+. Link them dynamically, keep them unmodified or publish your changes to them, include the licence and source offer in an Acknowledgements screen, and do not copy code from the VLC apps themselves (those are GPL).
- Some codecs and formats may carry patent considerations in certain regions; check before any public release.
- Never include DRM circumvention (e.g. encrypted Blu-ray decryption libraries).
- This is a personal app for now. Before shipping publicly, get proper legal advice on all of the above.

## Build order and working rules

Build in this order. Each milestone ends with a working app on both iPhone and Mac.

1. **Foundation:** project, packages, design system, VLCKit integrated, play a single file picked from Files/Finder in a basic player on both platforms.
2. **Engine:** `PlaybackEngine` protocol, both engines, router, event stream, track and subtitle switching, Now Playing, remote commands, background audio.
3. **Library v1:** sources, scanning, music tags and artwork, Music section (artists, albums, songs), mini-player and full Now Playing screen.
4. **Video library:** filename parsing, TMDB matching, Movies and TV Shows, detail pages, resume and watched state, Home with Continue Watching.
5. **Video player polish:** overlay controls, scrub thumbnails, info panel with every Level 2 option, PiP, AirPlay, macOS menus and shortcuts.
6. **VLC parity:** work through the feature coverage checklist row by row against the sample suite.
7. **Network:** SMB, UPnP, FTP/SFTP, NFS, streams, Chromecast.
8. **Extras:** queue polish, smart playlists, lyrics, equalizer, sleep timer, iCloud sync, widgets, App Intents, Handoff.
9. **Hardening:** accessibility pass, performance pass, tests, crash-free soak testing with a large real library.

### Working rules for you, the agent

- Before writing code that touches VLCKit, read the actual headers of the installed version. Do not invent API names.
- Keep the UI layer free of `import VLCKit`; only `PlaybackEngine` may import it.
- Prefer Apple frameworks over third-party packages; justify any dependency you add.
- After each milestone, summarise what was built, what is stubbed, and what deviates from this prompt and why.
- When a design decision is unclear, copy what Apple Music or the Apple TV app does on that platform, then ask me if it still seems wrong.
- Ask before making changes that affect the data model once real library data exists, and include a migration.
