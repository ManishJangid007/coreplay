# Coreplay milestones

| # | Milestone | Status |
| --- | --- | --- |
| 1 | Foundation: project, packages, design system, VLCKit, basic player on iPhone and Mac | Done |
| 2 | Engine: protocol, both engines, router, events, tracks and subtitles, Now Playing, remote commands, background audio | Done |
| 3 | Library v1: sources, scanning, music tags and artwork, Music section, mini player, Now Playing | Done (checked on the Mac) |
| 4 | Video library: filename parsing, TMDB, Movies and TV, detail pages, resume, Continue Watching | Built; builds and tests pass, needs a run with real videos |
| 5 | Video player polish: scrub thumbnails, every Level 2 option, PiP, AirPlay, macOS menus and shortcuts | Next |
| 6 | VLC parity: feature checklist against the sample suite | |
| 7 | Network: SMB, UPnP, FTP/SFTP, NFS, streams, Chromecast | |
| 8 | Extras: queue polish, smart playlists, lyrics, equalizer, sleep timer, iCloud sync, widgets, App Intents, Handoff | |
| 9 | Hardening: accessibility, performance, tests, soak testing | |

## Your additions (October 13)

These come on top of the plan; nothing in the plan was dropped for them.

| Request | Where it lands | Status |
| --- | --- | --- |
| Frame previews above the timeline while scrubbing, like YouTube | Milestone 5, with the scrub-preview sprite sheets the plan lists | The frame grabber it needs (`FrameGrabber`) is built |
| Video plays inside the app's own window, with every playback option in the player | Milestone 4 | Done on the Mac: the player covers the library in the same window (F for full screen, Esc to go back). iPhone and iPad already play full-screen inside the app. Options are behind the player's ••• button |
| Artwork for videos without any: a frame picked automatically, another frame of your choice, or your own image | Milestone 4 | Done (Choose Artwork) |
| An optional iPod-style Cover Flow view, with smooth scrolling | Milestone 4 | Done for Albums, Movies and TV Shows; the grid stays the default |
| Clicking the music artwork opens Now Playing in the same window, and its controls look right | Milestone 4 | Done on the Mac: Now Playing fills the window, with a new layout |
| One app that feels the same everywhere, with a very large library | Every milestone; measured in Milestone 9 | Ongoing |

---

## Milestone 4: Video library — October 13, 2026

### What was built

**Movies, TV shows and home videos** (new `VideoFeature` module)
- **Movies:** a poster grid sorted by title, recently added or release date, with an Unwatched Only filter and Cover Flow.
- **Movie pages:**
  - the backdrop with the title over it, and year, running time, age rating and genres;
  - badges for 4K, HDR10, HLG, Dolby Vision, Dolby Atmos, 5.1/7.1 and CC/SDH, read from the file;
  - Play or Resume, Play from Beginning, and a watched toggle;
  - tagline, synopsis, cast with photos, and an Information section (genre, release, directors, studio, picture, sound, languages, subtitles, file and size).
- **TV shows:** a poster grid, and show pages with:
  - a button for the episode to watch next ("Resume S2, E3", "Play S2, E4");
  - season tabs, with Specials last;
  - each season's episodes with stills, numbers, synopses, running times, progress bars and watched checkmarks;
  - Mark as Watched or Unwatched for an episode, a season or the whole show.
- **Home videos:** stills grouped by the month they were recorded, newest first. Tapping one plays it.
- **Where they appear:**
  - the iPhone's Videos tab (Movies, TV Shows, Home Videos, then recently added movies and shows) and the Mac sidebar's Videos section;
  - Home: Continue Watching (with progress and time left) and Up Next (the next episode of each show you're watching), before Recently Played music and Recently Added movies, shows and music;
  - Search: Movies, TV Shows, Episodes and Home Videos sections.

**Telling movies, episodes and home videos apart** (`VideoNameParser`)
- **Movies:** `Heat (1995).mkv`, release names (`The.Matrix.1999.1080p.BluRay.x264-GROUP`), or a `Heat (1995)` folder around the file. Titles containing years ("Blade Runner 2049", "1917", "2001 A Space Odyssey") keep them. Editions ("Director's Cut", Plex's `{edition-…}`) and `CD1`/`Part 2` are recognised.
- **Episodes:** `S01E02`, two-episode files (`S01E02E03`, `S01E02-E03`, `S01E02-03`), `1x02`, "Season 1 Episode 2", `Show/Season 1/02 - Title`, `Specials` folders (season 0), and anime-style `[Group] Show - 05`.
- **Home videos:** everything else, plus phone and camera names (`IMG_`, `VID_`, `PXL_`, `GOPR`, `DJI_`, dated names) even when they contain a year. A bare year, as in "Christmas 2019", only makes a movie when the video is feature length.
- **Per folder:** Sources ▸ right-click (or long-press) ▸ Videos in This Folder: Decide from Names, Movies, TV Shows or Home Videos. The folder's videos are sorted again straight away.
- **`.nfo` files** (as Kodi, Jellyfin, tinyMediaManager, Radarr and Sonarr write them) beside a video, or `tvshow.nfo` in a show's folder. Their details win over names and lookups. An `.nfo` that is only a link gives the IMDb or TMDB ID.
- **Artwork beside the files:** `Name-poster.jpg`, `poster.jpg` or `folder.jpg` (only when the movie has the folder to itself), `fanart.jpg`, episode `Name-thumb.jpg`, show and season posters (`season01-poster.jpg`, or a season folder's own poster), and cover art inside MKV and MP4 files.

**What's inside each file** (`VideoProbe`, reads headers only)
- **MP4, MOV and M4V:** codec, picture size, frame rate, HDR10 or HLG, Dolby Vision, each audio track's codec and language, the real channel count of Dolby Digital (Plus) tracks and their Atmos flag, subtitle tracks, and the recording date and place phones and cameras store.
- **Matroska and WebM:** the same, plus HDR10+, forced and SDH subtitle flags, chapters and cover attachments, including files whose track list comes after the video.
- **AVI:** picture size, codec, frame rate, length and audio.
- This is where running times (before a video has ever been played) and the badges come from.

**TMDB** (Settings ▸ Metadata, with your own key)
- **The key:** either TMDB credential works (the API key or the Read Access Token). It's checked when saved and kept in the Keychain.
- **Lookups** run in the background after scans, a few items at a time:
  - search by title and year (then without the year), and accept only a close title whose year is within one;
  - fetch details with cast and your region's age rating, the poster and backdrop, season posters, and episode titles, synopses, air dates and stills for the episodes you have;
  - IDs from `.nfo` files are used directly.
- **Corrections:** Fix Match (search TMDB and pick the right film or show), Look Up Again, and Settings ▸ Look Up Unmatched Titles Again. Edits and `.nfo` details are never replaced.

**Artwork for every video** (your addition)
- Videos with no artwork at all get a frame from about a tenth of the way in, two at a time in the background once lookups are done: AVFoundation for MP4 and MOV, VLC's thumbnailer for everything else (`FrameGrabber` in PlaybackEngine).
- A movie without a poster gets one made from that frame, with its title.
- **Choose Artwork** in any video's or show's menu: scrub to any frame and choose Use This Frame, or pick an image from Files, Finder or Photos. Use Automatic Artwork goes back.

**Watching**
- **Progress rules:**
  - videos resume where they stopped once past the first minute, with Play from Beginning beside Resume;
  - from 92% on they count as watched;
  - positions are saved every ten seconds, on pause and when something else starts (`WatchProgressTracker` and `ResumePolicy` in PlaybackCore).
- **Episodes** play on into the following ones. At the end of the last video the player closes, as in the TV app.
- **Subtitle files** beside a video (`Movie.srt`, `Movie.en.srt`, `.ass`, `.vtt`) are loaded with it.

**The player in the same window** (your additions, Mac)
- **Video and Now Playing open over the library** in the main window, instead of a separate window. F or the button toggles full screen. Esc, the back button or Playback ▸ Hide Player (⌥⌘P) returns to the library: video pauses, music plays on.
- **Now Playing on the Mac:**
  - the artwork beside the controls in wide windows, stacked in narrow ones;
  - buttons kept clear of the window's own controls, with hover states;
  - Up Next opens as a panel on the right;
  - Space and Esc work.

**Cover Flow** (your addition)
- Albums, Movies and TV Shows have a Grid / Cover Flow switch in the toolbar.
- Covers turn and stack as on the iPod, with reflections. Scroll, or use ← and →, then click the middle cover (or press Return) to open it.

**Data model** (`LibrarySchemaV2`, upgraded in place as you chose)
- **New models:** `Video` (a movie, an episode or a home video), `TVShow` and `Season`.
- **New fields:** `MediaFile` gains the video details, `Source` what its videos are, and `PlaybackRecord` watched state and running time.
- **The upgrade:** `LibrarySchemaV1` is now a frozen copy of Milestone 3's models, and `LibraryMigrationPlan` upgrades it to version 2 in place. Videos already in the library are read again on the first scan.
- **Who writes what:** videos, shows and seasons are only written by the scanner's context, one job at a time (scans, removals, lookups, frames). Play history is only written by the main context. So the two never collide.

### How it was checked
- **Linux:** 127 Swift Testing tests pass. New ones cover:
  - 45 video names (movies, episodes, home videos, folders and hints);
  - MP4 with Dolby Vision and Atmos, Matroska (including tracks after the media), AVI and camera dates, on files built byte by byte;
  - `.nfo` files, TMDB requests and responses, and matching;
  - the resume and watched rules.
- **Mac, through `Tools/build-check.sh` with Xcode 26.4.1:**
  - the Mac and iOS Simulator builds have no warnings;
  - all 139 tests pass;
  - **the upgrade is tested on a real Milestone 3 library.** Before any model changed, the Mac wrote a small library with the Milestone 3 code: a source, a song with an edited title, seven plays and a rating, and a video with a resume position. The test checks that the frozen copy matches that store exactly, then upgrades it and finds every value still there;
  - 3 new scanning tests: movies, a show with seasons, `tvshow.nfo` and posters, home videos; Edit Info surviving a folder being marked Home Videos; choosing and resetting artwork.
- **Not yet tested:**
  - a real video library and real TMDB lookups (there's no key yet);
  - VLC frames from real MKV files;
  - the new Mac layouts and Cover Flow, by eye;
  - anything on iPhone or iPad.

### Stubbed or deferred
- **Scrub previews** (your YouTube-style request) come in Milestone 5; the frame grabber they need is built.
- **Merging shows.** Two folders with different names that TMDB matches to the same show stay two shows.
- **Versions.** Two files of the same movie (1080p and 4K, say) appear as two movies, each with its badges.
- **Places.** Home video locations are read but not shown on a map yet.
- **TMDB options.** Lookups use the device's language; there's no choice of artwork language and no collections yet.
- **Player polish** (Picture in Picture, AirPlay details, the full info panel) is Milestone 5.

### Where this deviates from the build prompt, and why
1. **Movies, episodes and home videos share one `Video` model with a kind**, instead of separate Movie, Episode and HomeVideo models. They share almost every field, and Continue Watching, search and the player treat them alike. `TVShow` and `Season` are separate, as planned.
2. **Watched state and positions stay in `PlaybackRecord`**, by content fingerprint, not on the video. They survive rescans and moved files, only the main context writes them, and they can sync on their own later.
3. **Video details come from Coreplay's own container reader**, not VLC's parser or AVFoundation. It runs during scans without starting libVLC, reads MKV (which AVFoundation can't open), and is tested on any platform.
4. **A bare year only makes a movie when the video is long enough** (brackets or release-style names always do). Otherwise home videos such as "Christmas 2019" would be looked up as films.
5. **The separate Mac video window is gone**, replaced by the in-window player you asked for. The prompt's floating-on-top and multiple player windows can return in Milestone 5 as options.
6. **Cover Flow and choosing artwork weren't in the plan.** They're your additions.

---

## Milestone 3: Library v1 — October 13, 2026

### What was built

**Sources**
- **On iPhone and iPad:** the app's own folder ("On My iPhone ▸ Coreplay" in Files) is always a source, and any folder can be added from Files: iCloud Drive, an external drive or another app's folder. Access is kept with a security-scoped bookmark, so it survives relaunches.
- **On the Mac:** folders from an open panel (File ▸ Add Folder to Library…, ⇧⌘O) or dropped on the window, plus one-click Music and Movies folders.
- **The Sources screen** (Library ▸ Sources, or the Mac sidebar) has each source's song and video counts, scan progress, Check for New Files, Show in Finder on the Mac, and Remove from Library, which never deletes files.
- **Overlapping folders are refused.** Adding a folder that's inside another source, or that contains one, gives a clear message instead of duplicating songs.

**Scanning** (`MediaLibrary.LibraryIndexer`, a `@ModelActor` on a background context)
- **Incremental.** Unchanged files (same path, size and modification date) are never read again.
- **Concurrent reads.** Files are read sixteen at a time, and the library is saved every 128 files, so it fills in as the scan goes.
- **Nothing is deleted.** Files that vanish (a drive unplugged) are marked unavailable and shown dimmed, so their history survives.
- **When scans run:**
  - at launch;
  - on iOS, when the app returns to the foreground (at most every five minutes) and on pull to refresh;
  - on the Mac, when FSEvents reports a change in a source folder.
- **Cleanup.** Retagged songs move to their new album, and albums, artists and genres left empty are removed.

**Tags and artwork** (`MetadataProviders`, pure Swift)
- **Tag formats:**
  - ID3v2.2, 2.3 and 2.4 (Unicode text, unsynchronisation, and the non-standard frame sizes some old encoders wrote) and ID3v1;
  - FLAC and Ogg Vorbis comments, including embedded pictures;
  - MP4/M4A atoms, including compilation, disc numbers and MusicBrainz IDs;
  - APEv2;
  - WAV LIST/INFO, and ID3 chunks in WAV and AIFF.
- **Duration and format from the stream itself:**
  - MP3, from the Xing, VBRI or CBR headers;
  - AAC (ADTS), estimated from the frames;
  - FLAC, from STREAMINFO;
  - Ogg Vorbis and Opus, from granule positions;
  - MP4, from mvhd and stsd (ALAC's real sample rate and bit depth included);
  - WAV and AIFF.
- **Badges.** That stream information drives the "Lossless" and "Hi-Res Lossless" labels.
- **Names when tags are missing.** File and folder names fill the gaps: `Artist/Album (1997)/01 Title`, `Artist - Album/03. Title`, disc folders (`CD2`), iTunes-style `1-04 Title`, and `Artist - Title`.
- **Artwork order.** Embedded front cover, then `cover`, `folder`, `front` or `albumart` images in the same folder.
- **Artwork storage.** Each cover is stored once, by content, as 160, 600 and 1400 px JPEGs, so grids never decode full-size covers. Decoded images are cached in memory.

**Data model** (SwiftData, versioned as `LibrarySchemaV1` with a migration plan ready for later versions)
- **Files:** `Source` and `MediaFile`.
- **Music:** `Track`, `Album`, `Artist` and `Genre`.
- **History:** `PlaybackRecord` holds play counts, last played, and (later) positions and ratings.

**Music** (new `MusicFeature` module)
- **Albums:** a grid sorted by title, artist, recently added or year.
- **Album pages:**
  - large artwork, artist link, genre, year and quality;
  - Play and Shuffle;
  - tracks grouped by disc, with the song playing now marked;
  - swipe and context menus for Play Next and Play Later, and Edit Info.
- **Artists:** a list sorted the way Music sorts it, so "The Beatles" files under B. Artist pages have Albums, Appears On, and Songs.
- **Songs:** every song, with Play and Shuffle.
- **Genres:** a list, and pages with each genre's albums.
- **Edit Info:** title, artist, album, album artist, genre, year, track, disc and compilation. Each edit is remembered and never overwritten by a rescan.
- **Playing from the library:**
  - Apple Music's Play, Shuffle, Play Next and Play Later;
  - tapping a song plays from there through the list;
  - the mini player and Now Playing show the library's artwork and titles.
- **Home:** Recently Played and Recently Added shelves.
- **Search:** artists, albums, songs and videos, with All, Music and Videos scopes.
- **Home Videos:** lists every indexed video until Milestone 4 sorts them into movies and TV.
- **Play counts:** a song counts as played after half its length or four minutes of actual listening (`ListeningTracker`). Seeking doesn't count, and songs under 30 seconds never do.

### How it was checked
- **Linux:** 92 Swift Testing tests pass. The 33 new tag and file-name tests run on synthetic files built byte by byte (ID3v2.2/2.3/2.4, ID3v1, FLAC, Ogg Vorbis and Opus, MP4 with ALAC, WAV, AIFF and APE). There are also 9 play-count tests.
- **Mac, through `Tools/build-check.sh` with Xcode 26.4.1:**
  - the Mac and iOS Simulator builds have no warnings;
  - all 99 tests pass;
  - that includes 7 SwiftData tests that scan real temporary folders: tagged and untagged MP3s, embedded and folder artwork, compilations, incremental rescans, missing files, edits surviving a rescan, and removing a source.
- **Not yet tested:**
  - a real music library;
  - iCloud Drive and external-drive folders on iPhone;
  - FSEvents updates on the Mac.

### Stubbed or deferred
- **Online lookups.** MusicBrainz and Cover Art Archive (opt-in) come later, with LRCLIB lyrics.
- **Editing.** Edit Info works per song. Editing a whole album (title, artwork), artist photos, and Fix Match (which belongs to TMDB matching in Milestone 4) come later.
- **Sections.** Playlists (Milestone 8) and Composers aren't built yet. Movies and TV Shows say they're coming, and Home Videos lists every video for now.
- **Opened files.** Files opened with Open In or from Finder play but can't be added to the library from the player yet.
- **iOS background refresh.** Scheduled scans while the app isn't running aren't set up yet; scans happen at launch, on return to the app, and on pull to refresh.
- **Long lists.** There's no A–Z index on the side of long lists, and the performance pass with 50,000 songs is Milestone 9.

### Where this deviates from the build prompt, and why
1. **VLCMediaLibraryKit was evaluated and not used.** It keeps its own SQLite database and Objective-C model objects, so every screen would need a layer mapping it to SwiftData. It would also add a second VideoLAN binary that has to match the VLCKit build. Coreplay uses its own SwiftData indexer instead, which is the prompt's fallback.
2. **Tags are read by Coreplay's own Swift reader, not libVLC or TagLib.** It needs no extra dependency, runs on any thread without spinning up libVLC, and is tested on any platform. The trade-off is that WMA (ASF) tags aren't read yet; those files fall back to their names.
3. **`PlaybackState` is called `PlaybackRecord` and is keyed by a content fingerprint.** It isn't a relationship to `MediaFile`. The name avoids a clash with the engine's `PlaybackState`. The fingerprint (size plus the first and last 64 KB) keeps play history when files move or are renamed, and lets history sync on its own later.
4. **Recently Played and Recently Added arrived on Home early.** The prompt lists them with Home in Milestone 4.

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
**Xcode, October 13.** With Xcode 26.4.1 on macOS 26.6.2, the app builds for the Mac and the iOS Simulator with no warnings, and all 50 tests pass on the Mac. The first build turned up one compile error (AVFoundation's track type is a plain property, not one you load asynchronously). It also showed that the packages had to be referenced by folder for Xcode to run their tests and show their warnings. Both are fixed.

Before that first build, verification happened outside Xcode:

- **Unit tests on Linux.** The Foundation-only code (PlaybackCore and the queue) compiles with Swift 6.2 in Swift 6 mode, and 50 Swift Testing tests pass. They cover routing, containers, FourCC codes, option parsing, track naming and language matching, time formatting and queue behaviour.
- **VLCKit API names.** The real VLCKit 4.0.0a25 headers were imported through Clang. Every VLCKit call, and the Swift names of every delegate method, type-checks.
- **Concurrency checking.** The engine and NowPlaying sources were compiled with Swift 6 concurrency checking against stand-ins for Apple's frameworks, with no errors or warnings.
- **Race reproductions.** Reproductions of the engine-switching and VLC stop/end-of-media races pass after the fixes. A random-timing stress test ran 0 failures in 150 runs.
- **Project files.** The project file was parsed and every object reference resolves. Info.plist, the entitlements and the scheme are valid.

**Not done yet:** running the app on a simulator or a device and playing real files.

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

### Running it
1. Open `Coreplay.xcodeproj` in Xcode 26 or later.
2. Set `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`, or choose a team under Signing & Capabilities.
3. Let Swift Package Manager download VLCKit. It's large.
4. Run the **Coreplay** scheme on **My Mac** or an iPhone simulator. ⌘U runs the tests.
5. From Terminal, `bash Tools/build-check.sh` builds both platforms and runs the tests, with logs in `build/`.
