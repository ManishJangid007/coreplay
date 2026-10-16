# How Coreplay works

Notes for contributors: how the code is laid out, and how the library,
playback and networking work. To build and run the app, see
[Build from source](../README.md#build-from-source) in the README. What each
milestone built and changed is in [`Milestones.md`](Milestones.md), and the
original product brief is in
[`Build Prompt VLC-Powered Media Player for iOS & macOS.md`](../Build%20Prompt%20VLC-Powered%20Media%20Player%20for%20iOS%20%26%20macOS.md).

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
Widgets/              The widget extension (playback controls on the Home Screen
                      and the Mac's desktop)
Tools/                make_brand_assets.py (icons from Design/), build-check.sh
                      and build-watch.sh (command-line builds), make-dmg.sh
                      (the release disk image)
Packages/
  PlaybackEngine/     PlaybackCore (protocol, events, router, player options,
                      playlists, discs, track preferences; Foundation only)
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
  Networking/         Saved servers, logins in the Keychain, recent streams,
                      where network videos were left
```

The app target uses folder-synchronized groups: new files in `App/Coreplay` or
`App/Platform` are picked up without editing the project. Files under
`Platform/iOS` and `Platform/macOS` are wrapped in `#if os(…)`.

The packages are referenced by folder (the **Packages** group), so Xcode treats
them as part of the project: you can edit them, see their warnings and run their
tests. Don't re-add them with **Add Package Dependencies ▸ Add Local**, which makes
Xcode treat them as outside dependencies with hidden warnings and no tests.


## Tests

⌘U in Xcode runs the package tests (engine routing, queue behaviour,
formatting) on the Mac. The PlayerFeature tests also draw the player screens
to PNG files in `build/snapshots`, so their layout can be checked without
running the app, and the PlaybackEngine tests play a generated movie through
both engines in a small window (a lock-up is sampled into
`build/hang-<test>.txt`).

From Terminal, `bash Tools/build-check.sh` builds for macOS and the iOS
Simulator and runs the tests, with logs in `build/` (ignored by git).
`bash Tools/build-watch.sh` reruns that script whenever a `build/request`
file appears.

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
- **Discs** (switched off, see Player ▸ Discs): with `DiscLayout.canPlayDiscs`
  on, a folder holding VIDEO_TS or BDMV is one video (its VOB and M2TS files
  aren't listed on their own), and so is a DVD or Blu-ray image (`.iso`).
  Length, picture, sound and subtitle languages come from the DVD's IFO
  files or the Blu-ray's playlists (`DVDVideoInfo`, `BlurayInfo` in
  PlaybackCore), and artwork and `movie.nfo` from inside the folder, as Kodi
  keeps them. `MediaFile` marks a disc folder with the extension "dvd" or
  "bluray", so no schema change. While it's off, VOB and M2TS files are
  listed as videos and `.iso` files are skipped.
- **Video artwork**: anything without a poster or still gets a frame from
  about a tenth of the way in; Choose Artwork picks another frame or an image.
  VLC's thumbnailer scales a frame to exactly the box it's given, so
  `FrameGrabber` first reads the video's shape (pixel aspect included) with
  libVLC's parser and asks for a box of that shape.
- **Watched state** follows the TV app: resume after the first minute, watched
  from 92% on, or from the start of the end credits when a chapter marks
  them. Positions live in `PlaybackRecord`, by content fingerprint.
- **The hero carousel** at the top of Home, Movies, TV Shows and Albums
  features new arrivals, what you're in the middle of, then a pick of
  unwatched titles that changes daily (`FeaturedPicker`). It draws only the
  current page, so changing page never scrolls full-size artwork. The
  watchlist ("+") is a list of IDs in user defaults, so it needs no schema
  change.
- **Upgrades**: the schema is versioned (`LibrarySchemaV1`, `V2`, `V3`) with a
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
  applies them to whichever engine is playing. Subtitle style (font, colour,
  outline, background, height) and text encoding are options of the libVLC
  instance, so changing one restarts VLC at the same place with the same
  tracks; AVFoundation takes the style as text style rules. VLC can show a
  second subtitle track under the first.
- **Picture in Picture.** `PictureInPicture` wraps Apple's controller for
  AVFoundation and VLCKit 4's PiP protocols for VLC (the video view is the
  `VLCPictureInPictureDrawable`).
- **Scrub previews.** `ScrubPreviews` makes up to 200 small frames per local
  video in the background, coarse to fine, and keeps finished sets in
  Caches/Coreplay/Scrub Previews.
- **Preview clips.** The hero carousel's clips play in a second
  `PlaybackController` with the `.preview` purpose: no Picture in Picture,
  AirPlay, subtitles or scrub previews, and no audio output at all until
  you unmute (`PlaybackItem.playsAudio`), so other apps' music keeps playing.
- **One VLC picture at a time.** Two libVLC video outputs drawing at once
  trip libVLC's OpenGL checks, which end the app in VLCKit's development
  builds. So the main controller stops every preview (and waits for its
  output to go) before it opens anything, and a preview refuses VLC while the
  player has a video open. The real-media test suites run one at a time for
  the same reason.
- **VLC's video output on the Mac.** VLCKit's macOS default ("macosx") draws
  into an NSOpenGLView from VLC's own thread. Inside SwiftUI's layer-backed
  views it failed an OpenGL assertion whenever the view was resized as a
  video started (the player sliding in, the carousel turning a page).
  Coreplay asks for the Core Animation output (`--vout=caopengllayer`),
  which draws on the main thread in step with layout. While no player shows
  the video view, it waits in an invisible window (`VideoParking`). That
  window is ordered in only while it holds a view, because any visible
  window keeps SwiftUI from opening the main window at launch, and the app
  delegate reopens the main window from the Dock itself.
- **Up Next.** At an episode's end credits (a chapter named like "End
  Credits", or the last 20 seconds) the player offers the next queued episode
  and starts it after a countdown (`UpNextPolicy`). Settings ▸ Playback turns
  autoplay off; the next episode then waits on the last frame.
- **Turning, flipping and zoom** (`VideoTransform`, `VideoZoom`) are done by
  the video view, not the engine, so both engines can: the container's layer
  gets a `sublayerTransform` (`VideoPlacement` does the maths, about the
  layer's anchor, with the Mac's flipped y axis), and quarter turns swap the
  frame's shape. 360° videos (Google's `sv3d`, Apple's `prji`, the older
  spherical XML) go to VLC, which projects them; dragging and pinching move
  its viewpoint.
- **Discs.** A DVD or Blu-ray folder (or its VIDEO_TS, an IFO file in it, or
  an image) opens as the disc in VLC with its menus (`DiscLayout`). The
  player lists titles, shows a remote (arrows around Select) while a menu is
  on screen, and maps the arrow keys and Return to it. A disc resumes by
  choosing its film (the longest title), then seeking; progress counts only
  while the film plays. **All of this is off for now:** the official
  VLCKit 4.0.0a25 binaries are built with `--disable-dvdread
  --disable-dvdnav --disable-bluray`, so `DiscLayout.canPlayDiscs` is
  `false` and opening a disc says plainly that it can't play yet. A VLCKit
  built with disc support turns it back on with that one constant (the
  parity suite's disc tests run again then).
- **Playlists.** M3U/M3U8, PLS, XSPF and cue sheets are read by
  `PlaylistFile`. A cue sheet's tracks are `PlaybackSegment`s of one file:
  times count from the track's start, and the next track carries on without
  reopening the file.
- **Remembered per file** (`FileOptionsStore`, the last 500 files): tracks,
  timing, shape, crop, turn and deinterlacing come back the next time. When
  nothing is remembered, Settings ▸ Languages picks the audio and subtitles
  (`TrackPreferences`).
- **Loudness.** Volume goes to 200% with VLC. Sound Check levels music with
  ReplayGain (track or album) read from the tags; libVLC 4's volume
  normaliser can't be switched on from a player (its audio filter belongs to
  the equalizer), so there's no "normalise" for files without ReplayGain.
- **Captions.** When you haven't chosen a subtitle style, VLC follows
  Accessibility ▸ Subtitles & Captioning (`SystemCaptionStyle`), as
  AVFoundation does; only choices set to override video apply.
- **Online subtitles.** With your OpenSubtitles.com API key (Settings,
  kept in the Keychain), Subtitles ▸ Search OpenSubtitles finds subtitles by
  the file's hash, then by title or episode, and loads the one you pick.

## Playlists, lyrics and the rest of Milestone 8

- **Playlists** (`Playlist`, schema version 3) keep songs by content key, in
  order, so they survive rescans and match the same file on another device;
  songs the library doesn't have are counted, not shown. Add to Playlist is
  in every song's menu; a playlist reorders and removes like Up Next, and
  M3U, PLS and XSPF files import as playlists of the library songs they list.
- **Smart playlists** keep `SmartPlaylistRules` (PlaybackCore, tested on
  Linux): title, artist, album, genre, year, plays, length, date added and
  last played, matched all or any, ordered and limited.
- **Composers** come from the songs' tags.
- **Lyrics** in Now Playing (the quote button): the song's own tags, an
  `.lrc` file beside it, or LRCLIB when Settings ▸ Metadata ▸ Look Up
  Lyrics is on (off at first; title, artist, album and length are sent).
  Synced lyrics follow the song and a tap jumps to a line (`Lyrics` reads LRC).
- **Sleep timer** (the moon in Now Playing and the video player): 15 to 90
  minutes with a ten-second fade, or the end of the song or video.
- **Up Next** has Clear.
- **iCloud sync** (`LibraryCloudSync`) sends play counts, where videos got
  to, watched state, favourites and playlists through iCloud key-value
  storage, keyed by content fingerprint; each device scans its own files.
  It needs the **iCloud ▸ Key-value storage** capability, and iCloud needs a
  paid Apple Developer Program team (a free Personal Team can't sign it).
  The app checks for the entitlement: without it sync stays off, with no
  warning. With a paid team, add it under Signing & Capabilities for macOS
  and iOS and sync starts by itself.
- **Shortcuts and Siri** (`App/Coreplay/AppIntents.swift`): Play Playlist,
  Shuffle My Music, Play or Pause, Next, Previous and Open Network Stream.
- **Handoff:** what's playing appears on your other devices (a library file
  by content key, a stream or share by address) and carries on from the same
  place.
- **Widgets** (`Widgets/`): Coreplay Controls, small and medium, with
  previous, play/pause, next and (medium) Shuffle. The buttons are audio
  playback intents, which the system performs in the app.

## How networking works

Everything on the network goes through VLC, in PlaybackEngine (the only
code that imports VLCKit); the rest of the app sees plain values from
PlaybackCore (`NetworkProtocol`, `NetworkEntry`, `NetworkCredential`,
`StreamAddress`).

- **Shares** (SMB 1/2/3, FTP, SFTP, NFS, UPnP/DLNA) are browsed with
  `NetworkBrowser`: a folder's URL is parsed by libVLC and its sub-items are
  the files and folders in it, with sizes and dates where the server gives
  them. Sources ▸ Network lists saved servers and the ones found on the
  network; a folder plays what you tap and queues the rest of its videos
  (or songs) after it, with subtitle files of the same name.
- **Finding servers:** `NetworkDiscovery` runs VLC's local-network discovery
  modules (Bonjour, UPnP, and NetBIOS for Windows machines) while Sources is
  open.
- **Logins** are kept in the Keychain (`NetworkKeychain`, internet
  passwords per protocol, server, port and user), looked up just before a
  file plays and handed to VLC as per-item options (`smb-user`, `ftp-pwd`,
  …), never written into a URL or a file. When VLC needs one it doesn't
  have, its dialog provider asks (`NetworkLoginPrompt`, shown as a card over
  the app or the player), and Remember files it under that server.
- **Streams:** File ▸ Open Network Stream (⌘N), or Sources ▸ Open Network
  Stream: HTTP(S), HLS, MPEG-DASH, RTSP, RTMP, RTP/UDP multicast, MMS and SRT.
  HTTP files and HLS in formats Apple plays go to AVFoundation (so AirPlay
  works natively), everything else to VLC. The last 20 addresses are kept
  (never one with a password in it). Settings ▸ Network ▸ Stream Buffer is
  VLC's network caching.
- **Resume:** a video on a share carries on where it was left
  (`NetworkStore`, the last 300 videos, by address without the login).
- **Casting:** `CastingCenter` runs VLC's renderer discovery (Bonjour for
  Chromecasts, UPnP for DLNA TVs); the cast button beside AirPlay (video
  player and Now Playing) shows once a device is found. Choosing one moves playback to VLC at the same place and sends
  it to the device; the player shows "Playing on …".
- **Permissions:** iOS asks for local network access the first time Sources
  is opened (`NSBonjourServices` lists the services VLC looks for). On the
  Mac the sandbox needs `network.server` too: UPnP discovery listens for
  replies, and a Chromecast pulls the video from VLC.

## Brand

The app icon (iOS full-bleed and macOS tile, all sizes) and the in-app logo
(`Brand.logo` / `BrandLogo` in DesignSystem) are bitmaps exported from
`Design/Coreplay-logo-source.png` by `Tools/make_brand_assets.py`. The accent
colour is the cone's orange (`#E06500`, `#EB6E05` in dark mode), which keeps
3:1 contrast with white labels and on black.
