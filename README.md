# Coreplay

VLC's engine, Apple's experience, the user's own library. A personal media
player for iPhone, iPad and Mac that plays anything VLC can play and feels like
Apple Music and the Apple TV app.

The full product brief is in
[`Build Prompt VLC-Powered Media Player for iOS & macOS.md`](Build%20Prompt%20VLC-Powered%20Media%20Player%20for%20iOS%20%26%20macOS.md).
Progress against it is tracked in [`Docs/Milestones.md`](Docs/Milestones.md).

## Requirements

- Xcode 26 or later (Swift 6.2 toolchain)
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

⌘U runs the unit tests in the packages (engine routing, queue behaviour,
formatting). The pure-Swift parts also build and test with plain
`swift test` from `Packages/PlaybackEngine` and `Packages/NowPlaying` on a Mac.

## Layout

```
App/
  Coreplay/           App entry, AppModel (opening files, presentation), assets
  Platform/iOS/       Tab bar + mini player accessory, full-screen player, Files picker
  Platform/macOS/     Sidebar window, playback bar, video window, menus, Finder/Dock opening
  Support/            Info.plist (document types, background audio), macOS entitlements
Config/Base.xcconfig  Team, bundle ID prefix, version
Design/               Source artwork for the logo and app icon
Docs/Milestones.md    Status, and what each milestone built, stubbed and changed
Tools/                make_brand_assets.py: regenerates the icons from Design/
Packages/
  PlaybackEngine/     PlaybackCore (protocol, events, router; Foundation only)
                      PlaybackEngine (VLCKitEngine, AVPlayerEngine, prober,
                      PlaybackController, VideoSurface). The only code that imports VLCKit.
  NowPlaying/         PlaybackSession, Up Next queue, MPNowPlayingInfoCenter,
                      remote commands, audio session
  DesignSystem/       Palette, metrics, motion, artwork views, artwork-derived
                      backgrounds, scrubber and transport controls
  Features/           HomeFeature, LibraryFeature, SearchFeature, PlayerFeature, SettingsFeature
  MediaLibrary/       Placeholder (Milestones 3–4)
  MetadataProviders/  Placeholder (Milestones 3–4, 8)
  Networking/         Placeholder (Milestone 7)
```

The app target uses folder-synchronized groups: new files in `App/Coreplay` or
`App/Platform` are picked up without editing the project. Files under
`Platform/iOS` and `Platform/macOS` are wrapped in `#if os(…)`.

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
- **Video.** Both engines render into one `PlatformVideoView` owned by the
  controller. `VideoSurface` borrows it while on screen, so re-opening the
  player never rebuilds VLC's video output, and VLC is never allowed to open
  a window of its own.

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
