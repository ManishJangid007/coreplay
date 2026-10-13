# Coreplay

VLC's engine, Apple's experience, the user's own library. A personal media
player for iPhone, iPad and Mac that plays anything VLC can play and feels like
Apple Music and the Apple TV app.

The full product brief is in
[`Build Prompt VLC-Powered Media Player for iOS & macOS.md`](Build%20Prompt%20VLC-Powered%20Media%20Player%20for%20iOS%20%26%20macOS.md).
Progress against it is tracked in [`Docs/Milestones.md`](Docs/Milestones.md).

## Requirements

- Xcode 26 or later (last built with Xcode 26.4.1 on macOS 26.6)
- iOS / iPadOS 26 and macOS 26 deployment targets (one multiplatform target, native macOS, not Catalyst)
- An Apple ID added in Xcode ▸ Settings ▸ Accounts for signing

## Getting started

1. Open `Coreplay.xcodeproj`.
2. Set your team: either put your Team ID in `Config/Base.xcconfig`
   (`DEVELOPMENT_TEAM = ABCDE12345`) or pick it under the Coreplay target ▸
   Signing & Capabilities. Change `BUNDLE_ID_PREFIX` there too if you like.
3. Wait for package resolution. The first resolve downloads the official
   VLCKit 4.0.0a25 XCFramework from download.videolan.org (it's large).
4. Choose the **Coreplay** scheme and a destination (**My Mac**, an iPhone
   simulator or a device) and run.
5. Open a file: **File ▸ Open…** (⌘O), drag files onto the window, or
   double-click a media file and choose Coreplay on the Mac; the **+** button
   or "Open Files…" on iPhone and iPad, or "Open in Coreplay" from Files.

⌘U runs the package tests (engine routing, queue behaviour, formatting) on
the Mac. The PlayerFeature tests also draw the player screens to PNG files in
`build/snapshots`, so their layout can be checked without running the app, and
the PlaybackEngine tests play a generated movie through both engines in a small
window (a lock-up is sampled into `build/hang-<test>.txt`). From Terminal, `bash Tools/build-check.sh` builds for macOS and the
iOS Simulator and runs the tests, with logs in `build/` (ignored by git).
`bash Tools/build-watch.sh` reruns that script whenever a `build/request` file
appears, so Claude can start builds while you're away from the keyboard.

## Layout

```
App/
  Coreplay/           App entry, AppModel (opening files, presentation), assets
  Platform/iOS/       Tab bar + mini player accessory, full-screen player, Files picker
  Platform/macOS/     Sidebar window, playback bar, the player over the window, menus,
                      Finder/Dock opening
  Support/            Info.plist (document types, background audio), macOS entitlements
Config/Base.xcconfig  Team, bundle ID prefix, version
Design/               Source artwork for the logo and app icon
Docs/Milestones.md    Status, and what each milestone built, stubbed and changed
Tools/                make_brand_assets.py (icons from Design/), build-check.sh
                      and build-watch.sh (command-line builds)
Packages/
  PlaybackEngine/     PlaybackCore (protocol, events, router, player options;
                      Foundation only)
                      PlaybackEngine (VLCKitEngine, AVPlayerEngine, prober,
                      PlaybackController, VideoSurface, Picture in Picture,
                      scrub previews). The only code that imports VLCKit.
  NowPlaying/         PlaybackSession, Up Next queue, MPNowPlayingInfoCenter,
                      remote commands, audio session
  DesignSystem/       Palette, metrics, motion, artwork views, artwork-derived
                      backgrounds, scrubber and transport controls, shelves,
                      badges, Cover Flow
  Features/           HomeFeature, MusicFeature, VideoFeature (movies, shows,
                      home videos, Fix Match, artwork), LibraryFeature (Sources),
                      SearchFeature, PlayerFeature (video player, Now Playing,
                      the options panel), SettingsFeature
  MediaLibrary/       SwiftData model (versioned, with migrations), sources and
                      bookmarks, the scanner, TMDB and keyless lookups, video
                      frames as artwork, artwork cache, play counts and watched
                      state, Edit Info
  MetadataProviders/  Embedded tag reader (ID3, FLAC/Ogg, MP4, APE, WAV/AIFF),
                      file-name fallbacks, name keys, video names and container
                      details (MP4, MKV, AVI), .nfo files, the TMDB, TVmaze
                      and Wikipedia clients
  Networking/         Placeholder (Milestone 7)
```

The app target uses folder-synchronized groups: new files in `App/Coreplay` or
`App/Platform` are picked up without editing the project. Files under
`Platform/iOS` and `Platform/macOS` are wrapped in `#if os(…)`.

The packages are referenced by folder (the **Packages** group), so Xcode treats
them as part of the project: you can edit them, see their warnings and run their
tests. Don't re-add them with **Add Package Dependencies ▸ Add Local**, which makes
Xcode treat them as outside dependencies with hidden warnings and no tests.

## How the library works

```
 Sources (folders, "On My iPhone", ~/Music)  ──▶  LibraryIndexer (background SwiftData context)
                                                    │  songs: TagReader + PathMetadata
                                                    │  videos: VideoProbe + VideoNameParser + .nfo + local posters
                                                    │  then lookups (TMDB, or TVmaze and Wikipedia) and frames
                                                    │  ArtworkStore: thumbnail, grid and large JPEGs
                                                    ▼
          Source · MediaFile · Track · Album · Artist · Genre · Video · TVShow · Season · PlaybackRecord
                                                    │
                     @Query in the library, Home and Search screens · LibraryManager for everything else
```

- **Sources** are folders the user picks (kept as security-scoped bookmarks),
  the app's own Documents folder on iPhone and iPad, and the Music and Movies
  folders on the Mac. A source's folder stays accessible while the app runs.
- **Scans are incremental.** Files are matched by path; only new files and
  files whose size or modification date changed are read. Files that disappear
  are marked unavailable, not deleted. Scans run when the app starts, when it
  returns to the foreground on iOS (at most every five minutes), on pull to
  refresh, and on the Mac whenever FSEvents reports a change.
- **Metadata** comes from embedded tags first, then folder and file names
  (`Artist/Album (Year)/01 Title.flac` and friends). Artwork comes from the
  file, then `cover.jpg`, `folder.jpg` and similar in the same folder.
- **Grouping** follows Music: albums by album artist and title, compilations
  under Various Artists, "The" ignored when sorting.
- **Edit Info** changes are remembered per field and never overwritten by a rescan.
- **Play counts** use a content fingerprint, so history survives moving a file.
  A song counts as played after it has played for half its length or four minutes.
- **Videos** are sorted by their names into movies (`Heat (1995).mkv`),
  episodes (`Show S01E02.mkv`, `Show/Season 1/02.mkv`) and home videos
  (everything else, phone and camera names included). Sources ▸ Videos in
  This Folder overrides that per folder. `.nfo` files and `poster.jpg` /
  `fanart.jpg` beside the videos win over names.
- **TMDB** (Settings ▸ Metadata, with your own key) fills in posters,
  backdrops, synopses, cast and episode titles, a few items at a time in the
  background. Fix Match picks a different entry; Edit Info changes stick.
- **Without a key**, TVmaze fills in TV shows and Wikipedia (with Wikidata)
  fills in movies: posters, synopses, and episode titles and stills. Movie
  and show pages credit them, as CC BY-SA asks. Settings ▸ Metadata ▸ Free
  Sources turns them off; adding a TMDB key replaces their results.
- **Video artwork**: anything without a poster or still gets a frame from
  about a tenth of the way in; Choose Artwork picks another frame or an image.
- **Watched state** follows the TV app: resume after the first minute, watched
  from 92% on. Positions live in `PlaybackRecord`, by content fingerprint.
- **Upgrades**: the schema is versioned (`LibrarySchemaV1`, `V2`) with a
  migration plan, and a test opens a real version 1 library to prove it.

## How playback works

```
 UI (SwiftUI)  ──▶  PlaybackSession (queue, Now Playing, remote commands, audio session)
                          │
                          ▼
                    PlaybackController  ──▶  EngineRouter (pure)  ◀──  MediaProber (AVFoundation probe)
                     │        ▲
          load/play  │        │  AsyncStream<PlaybackEvent>
                     ▼        │
            VLCKitEngine  or  AVPlayerEngine  ──▶  PlatformVideoView (one long-lived view)
```

- **Routing.** AVFoundation plays an item only when the container and every
  audio, video and subtitle track are natively supported (for example
  H.264/HEVC/Dolby Vision with AAC/AC-3/E-AC-3 in MP4, or MP3/AAC/ALAC/FLAC).
  MKV, AVI, WMV, Ogg, Opus, DTS, TrueHD, PGS/ASS subtitles, non-HTTP protocols
  and anything that fails to probe go to VLC. Settings ▸ Advanced has "Always
  Use VLC Engine"; items carry their own `enginePreference`.
- **Handoff.** If you ask for something AVFoundation can't do (subtitle or
  audio timing, an external subtitle file, more than 2× speed) or AVFoundation
  fails to open a file, the controller moves playback to VLC at the same
  position, keeping speed, volume and track languages.
- **Events.** VLCKit 4 calls its delegate on libVLC threads; a small bridge
  turns those calls into values on an `AsyncStream`, consumed on the main
  actor. AVFoundation KVO, notifications and time observers hop to the main
  actor explicitly. Nothing depends on which thread a framework calls back on.
- **Threads.** libVLC calls that reach into a running video output (picture
  options, the equalizer, snapshots) run on the VLC engine's own queue, never
  the main thread: the output takes its lock while it waits for the main
  thread to set up its view, so those calls would deadlock there.
- **Video.** Both engines render into one `PlatformVideoView` owned by the
  controller. `VideoSurface` borrows it while on screen, so re-opening the
  player never rebuilds VLC's video output, and VLC is never allowed to open
  a window of its own.
- **Options.** Shape, crop, colours, deinterlacing, channels, the equalizer
  and subtitle size are VLC's, so choosing one hands an AVFoundation item to
  VLC at the same position. The controller keeps the chosen options and
  applies them to whichever engine is playing.
- **Picture in Picture.** `PictureInPicture` wraps Apple's controller for
  AVFoundation and VLCKit 4's PiP protocols for VLC (the video view is the
  `VLCPictureInPictureDrawable`).
- **Scrub previews.** `ScrubPreviews` makes up to 200 small frames per local
  video in the background, coarse to fine, and keeps finished sets in
  Caches/Coreplay/Scrub Previews.

## Brand

The app icon (iOS full-bleed and macOS tile, all sizes) and the in-app logo
(`Brand.logo` / `BrandLogo` in DesignSystem) are bitmaps exported from
`Design/Coreplay-logo-source.png` by `Tools/make_brand_assets.py`. The accent
colour is the cone's orange (`#E06500`, `#EB6E05` in dark mode), which keeps
3:1 contrast with white labels and on black.

The current artwork combines Apple's logo and VLC's cone, which is fine for a
personal build but has to be replaced before any public release (see
`Docs/Milestones.md`).

## Licensing

VLCKit and libVLC are LGPL 2.1 or later. Coreplay links the official VLCKit
binary dynamically and unmodified, and shows the licence and source offer in
Settings ▸ About ▸ Acknowledgements. No code is copied from the GPL-licensed VLC
apps. This is a personal project; get legal advice before any public release.

TVmaze and Wikipedia text is CC BY-SA, credited where it appears. Many film
posters on Wikipedia are non-free images used there under fair use: fine for a
personal library, but check before shipping them in a public app.
