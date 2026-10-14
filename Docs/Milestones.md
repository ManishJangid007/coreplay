# Coreplay milestones

| # | Milestone | Status |
| --- | --- | --- |
| 1 | Foundation: project, packages, design system, VLCKit, basic player on iPhone and Mac | Done |
| 2 | Engine: protocol, both engines, router, events, tracks and subtitles, Now Playing, remote commands, background audio | Done |
| 3 | Library v1: sources, scanning, music tags and artwork, Music section, mini player, Now Playing | Done (checked on the Mac) |
| 4 | Video library: filename parsing, TMDB, Movies and TV, detail pages, resume, Continue Watching | Done (checked on the Mac) |
| 5 | Video player polish: scrub thumbnails, every Level 2 option, PiP, AirPlay, macOS menus and shortcuts | Built; builds and tests pass, needs a run with real videos and on iPhone |
| 6 | VLC parity: feature checklist against the sample suite | Done (checked on the Mac); DVD and Blu-ray wait for a VLCKit built with disc support |
| 7 | Network: SMB, UPnP, FTP/SFTP, NFS, streams, Chromecast | Done (checked on the Mac); indexing shares into the library waits for your go-ahead (a data model change) |
| 8 | Extras: queue polish, smart playlists, lyrics, equalizer, sleep timer, iCloud sync, widgets, App Intents, Handoff | Done (checked on the Mac); iCloud sync needs one capability switched on in Xcode |
| 9 | Hardening: accessibility, performance, tests, soak testing | Done (checked on the Mac); a run on an iPhone and Instruments on a device are yours to do |

## Your additions (October 13)

These come on top of the plan; nothing in the plan was dropped for them.

| Request | Where it lands | Status |
| --- | --- | --- |
| Frame previews above the timeline while scrubbing, like YouTube | Milestone 5 | Done: drag the scrubber, or hover over it on the Mac |
| Video plays inside the app's own window, with every playback option in the player | Milestones 4 and 5 | Done: the player opens over the library in the same window, and its ••• button opens every option in a panel over the video |
| Artwork for videos without any: a frame picked automatically, another frame of your choice, or your own image | Milestone 4 | Done (Choose Artwork) |
| An optional iPod-style Cover Flow view, with smooth scrolling | Milestone 4 | Done for Albums, Movies and TV Shows; the grid stays the default |
| Clicking the music artwork opens Now Playing in the same window, and its controls look right | Milestones 4 and 5 | Done: Now Playing fills the window, with the new controls |
| Movie and show artwork found from the name, with a free source | Milestone 5 | Done: TVmaze for TV shows and Wikipedia for movies, with no key |
| Native-looking player controls instead of boxy ones, with room around the icons (the subtitle button was squeezed) | Milestone 5 | Done for the video player, Now Playing and the Mac playback bar |
| One app that feels the same everywhere, with a very large library | Every milestone; measured in Milestone 9 | Ongoing |
| A hero carousel like the TV app and Netflix: full artwork for movies and shows, and a short clip playing for movies | Added during Milestone 6 | Done: Home, Movies and TV Shows (see below) |
| A series page with the episodes, the one last played, and a seamless way to carry on | Added during Milestone 6 | Done: show page redesign and Up Next at the end credits (see below) |
| Music lists that look like charts, not plain lists | Added during Milestone 6 | Done: chart rows, Top Songs, genre tiles and artist portraits (see below) |

---

## Milestone 9: Hardening — October 14, 2026

### Accessibility

- **VoiceOver:** every control has a label, checked across the feature code (icon-only buttons, the new cast, sleep-timer and lyrics controls, network rows, the widget's buttons). The scrubbers and sliders are adjustable (swipe up or down), and rows read as one element.
- **Subtitles & Captioning:** VLC now follows the choices in Accessibility ▸ Subtitles & Captioning (text colour, background, outline, font) whenever you haven't picked a style in Coreplay, as AVFoundation already did. Only choices set to override video apply, so the default look doesn't change. SDH and CC tracks were already labelled.
- **Increase Contrast** brightens the player's secondary text. **Reduce Motion** turns off the lyrics scrolling and the artwork and hover animations (as it already did elsewhere). **Reduce Transparency** is honoured by the system materials the app uses.
- **Keyboard:** the Mac menus and shortcuts cover playback, tracks, subtitles, the stream sheet (⌘N) and the player; standard controls work with Full Keyboard Access.

### Performance

- **A large library** test builds 10,000 songs and times what people open most. On the Mac: every song 0.5 s (it was 1.2 s before songs and their files were fetched in one query), a smart playlist over all of them 1.5 s, a 5,000-song playlist 0.19 s, Top Songs under 0.01 s. Smart playlists are worked out when you open one, so a very large library waits a moment there; making that incremental is the next step if it bothers you.
- Lists and grids are lazy, artwork is decoded off the main thread at the size it's shown, Top Songs is a limited query, and network folders load in the background.

### Tests

- **342 package tests pass on the Mac**, and the Foundation-only ones on Linux too. They cover the filename parser, the engine router, metadata matching, progress and resume rules, the queue, both engines against the parity sample suite, network shares and streams against local FTP and HTTP servers, playlists, smart playlists, iCloud sync and library upgrades.
- **Soak:** 50 files opened one after another in quick succession across both engines, with seeks in between: no crash, no hang (a watchdog checks the main thread), no stuck item, and the next file plays normally.

### Not done here, and why

- **UI tests (XCUITest)** for the core flows: running them needs Accessibility permission for the test runner and a signed app on your Mac, which the unattended build machine can't grant. The flows they'd cover (open, browse, play, track switching, resume, playlists) are tested one level down, through the same controller and session the screens use, plus snapshot pictures of the screens.
- **Instruments, launch time, 4K memory and 120 Hz scrolling** have to be measured on your devices; nothing here suggests a problem, but these numbers haven't been taken.
- **Free metadata sources (TVmaze, Wikipedia) are on by default**, where the build prompt asks for every lookup to be opt-in. Turning them off now would stop lookups for your existing library without asking you; one switch in Settings ▸ Metadata does it.

---

## Milestone 8: Extras — October 14, 2026

### What was built

- **Playlists:** New Playlist, Add to Playlist in every song's menu, reorder and remove (as in Up Next), rename and delete. Playlists show as tiles with a mosaic of their covers, and a playlist page in the same chart style as the music lists.
- **Smart playlists:** rules on title, artist, album, genre, year, plays, length, date added and last played; all or any of them; a limit and an order (most played, recently added, random…). Recently Added, Most Played and Never Played are there to start from.
- **Imported playlists:** M3U, PLS and XSPF files become playlists of the library songs they list; songs that aren't in the library are counted.
- **Composers** in the Music sidebar (and the Music tab on iPhone).
- **Lyrics:** a Lyrics button in Now Playing. Synced lyrics follow the song with the current line bright, and a tap on a line jumps there. They come from the song's tags, an `.lrc` file beside it, or LRCLIB when Look Up Lyrics is on (Settings ▸ Metadata; off at first).
- **Sleep timer:** the moon in Now Playing and the video player: 15, 30, 45, 60 or 90 minutes (the sound fades out over the last ten seconds), or the end of the song or video.
- **Queue:** Clear in Up Next (reordering, removing, history, Play Next and Play Later were already there).
- **Equalizer:** already in place since Milestone 5 (presets and ten bands, in Options ▸ Sound).
- **iCloud sync:** play counts, where videos got to, watched state, favourites and playlists, by content fingerprint, so the same file on the iPhone and the Mac shares its history. Each device keeps scanning its own files.
- **Shortcuts and Siri:** Play Playlist, Shuffle My Music, Play or Pause, Next, Previous and Open Network Stream, with phrases such as “Play Road Trip in Coreplay”.
- **Handoff:** what's playing appears on your other devices and carries on from the same place.
- **Widget:** Coreplay Controls (small and medium) with previous, play/pause, next and Shuffle, on the Home Screen and the Mac's desktop.

### How it was checked

- **Builds:** macOS and the iOS Simulator, with the new widget extension embedded in both.
- **Tests on the Mac:** 340 package tests pass. New ones: playlist order, moves and removals with a song only on another device; smart playlists from rules and play counts; iCloud sync between two libraries through a stand-in store (counts, progress, playlists, then a deletion travelling back); an old library upgrading to version 3 with its videos and a new playlist.
- **Tests on Linux:** LRC reading (offsets, several stamps a line, plain text), the line playing at a time, smart playlist rules, ordering and limits, LRCLIB requests and replies, and Clear Up Next.
- **Not yet checked by hand:** Siri phrases, Handoff and the widget on devices, and iCloud sync (it needs the capability below).

### Stubbed or deferred

- **iCloud sync needs one switch:** Signing & Capabilities ▸ + Capability ▸ iCloud ▸ Key-value storage on the Coreplay target. I didn't turn it on, because it needs your developer team and would stop the app building if the team can't use iCloud. Until it's on, nothing syncs and nothing else changes.
- **The widget shows controls, not what's playing:** showing the song would need an App Group shared between the app and the widget, which (like iCloud) depends on your team's capabilities.
- **Settings and the watchlist aren't synced** (the watchlist names movies by this device's library IDs).

### Where this deviates from the build prompt, and why

1. **iCloud key-value storage instead of CloudKit.** It syncs what you did (counts, progress, playlists) by content fingerprint, which works across devices that each scan their own files. Syncing the library database itself through CloudKit would duplicate every song a device scans and can't express “the same file on another device”.
2. **Library metadata edits (Edit Info, Fix Match) stay on the device** that made them, for the same reason.

---

## Milestone 7: Network — October 14, 2026

### What was built

**Shares** (Sources ▸ Network)
- **Connect to Server:** SMB, SFTP, FTP or NFS, with an address such as `nas.local/Movies`, `\\SERVER\Share` or `smb://…`, a user name, password and (for SMB) a Windows domain. The folder is opened before the server is kept, so a wrong password shows straight away. Edit and Forget are in each server's menu.
- **On this network:** Macs, PCs and NAS drives that announce their shares (Bonjour), Windows machines (NetBIOS) and UPnP/DLNA media servers appear by themselves while Sources is open.
- **Folders:** folders first, with sizes and dates, Filter, Play All and Reload. A video plays and the folder's other videos queue after it, so a season carries on; songs queue the same way. Subtitle files with the video's name come with it.
- **Logins** are kept in the Keychain. When a server asks for one Coreplay doesn't have, VLC's own request appears as a card over the app or the player, and Remember keeps it.
- **Resume:** a video on a share carries on where you left it (the last 300).

**Streams**
- **File ▸ Open Network Stream…** (⌘N), also in Sources: HTTP(S), HLS, MPEG-DASH, RTSP, RTMP, RTP and UDP multicast, MMS and SRT. It names the kind of stream as you type and keeps the last 20 (never one with a password in it). Stream Buffer is in Settings ▸ Network.
- HTTP files and HLS in formats Apple plays go to AVFoundation, so AirPlay works as usual; everything else goes to VLC.

**Casting**
- A cast button beside AirPlay (video player and Now Playing) once a Chromecast or a DLNA TV is found. Choosing one moves playback to VLC at the same place and the player shows “Playing on …”; This Device brings it back.

### How it was checked

- **Builds:** macOS and the iOS Simulator build cleanly.
- **Tests on the Mac:** 330 package tests pass. New ones run an FTP server and an HTTP server inside the test process: a folder listed with a saved login (sizes, subtitle files, folders first, a folder inside), VLC asking for a login through its dialog provider and the answer going back, a wrong password failing plainly, a video played from FTP with the Keychain login handed to VLC, and HTTP files on both engines with byte ranges.
- **Your network:** the discovery test found your Mac's SMB and SFTP shares and its NetBIOS name, and your Sony Bravia (DLNA) as a cast target.
- **Tests on Linux:** addresses (typed, Windows-style, IPv6), logins as VLC options, file kinds and sorting, stream addresses and kinds, recent streams, saved servers and resume points.
- **Not yet checked by hand:** casting to a TV or Chromecast, SMB, SFTP and NFS servers (the modules are in VLCKit and use the same code as FTP), and an iPhone run.

### Stubbed or deferred

- **Indexing shares into the library** (the build prompt's “optionally indexed”): it needs a change to the library's data model (a network kind of source), and the build prompt asks me to check with you first. Browsing and playing don't need it.
- **Scrub previews** are still made for local files only.
- **WebDAV:** VLC has no WebDAV browser; files on a WebDAV server play by their http(s) address.

### Where this deviates from the build prompt, and why

1. **On iPhone and iPad, UPnP, NetBIOS and DLNA TVs need Apple's multicast networking entitlement** (they talk to the whole network), which Apple grants per app on request. Until it's granted iOS blocks them; Bonjour discovery (most Macs, NAS drives and Chromecasts) works. The Mac has no such limit.
2. **Saved logins go to VLC as per-item options** (`smb-user`, `ftp-pwd`…) rather than through its dialog; the dialog is still used whenever a login is missing or wrong.
3. **VLC keeps a login that worked in memory until the app quits,** so a password changed on the server keeps working until Coreplay is relaunched.

---

## Milestone 6: VLC parity — October 14, 2026

### The checklist

Every row of the build prompt's VLC checklist, with the sample that covers
it (Tests/ParitySamples, made by `Tools/make_parity_samples.py`) and what
the Mac's test run found (`build/parity-report.md`).

| Feature | Sample | Engine | Result |
| --- | --- | --- | --- |
| Discs: VIDEO_TS folder with a menu | `dvd` | VLC | Recognised as a DVD; waits for a VLCKit with disc support (deviation 4) |
| Discs: DVD ISO image | `dvd.iso` | VLC | Recognised as a DVD; waits for a VLCKit with disc support (deviation 4) |
| Formats: H.264 and AAC in MP4 | `h264-aac.mp4` | AVFoundation | Plays |
| Formats: HEVC in MP4 | `hevc-aac.mp4` | AVFoundation | Plays |
| Formats: HEVC 10-bit, HDR10; Audio: AC-3 | `hevc10-hdr10.mkv` | VLC | Plays |
| Formats: HEVC 10-bit, HLG | `hevc10-hlg.mp4` | AVFoundation | Plays |
| Formats: VP9 and Opus in WebM | `vp9-opus.webm` | VLC | Plays |
| Formats: AV1 | `av1-opus.webm` | VLC | Plays |
| Formats: VP8 and Vorbis | `vp8-vorbis.webm` | VLC | Plays |
| Formats: MPEG-4 Part 2 (Xvid) and MP3 in AVI | `xvid-mp3.avi` | VLC | Plays |
| Formats: MPEG-2 and AC-3 in MPEG-TS | `mpeg2-ac3.ts` | VLC | Plays |
| Formats: MPEG-2 and MP2 in MPEG-PS | `mpeg2-mp2.mpg` | VLC | Plays |
| Formats: Theora in Ogg | `theora-vorbis.ogv` | VLC | Plays |
| Formats: WMV and WMA in ASF | `wmv2-wma.wmv` | VLC | Plays |
| Formats: FLV | `h264-aac.flv` | VLC | Plays |
| Formats: ProRes and PCM in QuickTime | `prores-pcm.mov` | AVFoundation | Plays |
| Formats: 3GP | `mpeg4-aac.3gp` | AVFoundation | Plays |
| Audio: DTS | `h264-dts.mkv` | VLC | Plays |
| Audio: Dolby TrueHD | `h264-truehd.mkv` | VLC | Plays |
| Audio: FLAC in Matroska | `h264-flac.mkv` | VLC | Plays |
| Audio tracks: two languages, named tracks; Audio: E-AC-3 | `two-audio-tracks.mkv` | VLC | Plays |
| Subtitles: ASS with styling, SRT and WebVTT inside Matroska | `subtitles.mkv` | VLC | Plays |
| Subtitles: 3GPP timed text in MP4 | `mov-text.mp4` | AVFoundation | Plays |
| Subtitles: external SRT and WebVTT files | `sidecar.mkv` | VLC | Plays |
| Navigation: chapters | `chapters.mkv` | VLC | Plays |
| Audio: FLAC with ReplayGain tags | `tone-replaygain.flac` | AVFoundation | Plays |
| Audio: Opus | `tone.opus` | VLC | Plays |
| Audio: Vorbis | `tone.ogg` | VLC | Plays |
| Audio: ALAC | `tone-alac.m4a` | AVFoundation | Plays |
| Audio: WMA | `tone.wma` | VLC | Plays |
| Audio: E-AC-3 in Matroska audio | `tone.mka` | VLC | Plays |
| Audio: AIFF | `tone.aiff` | AVFoundation | Plays |
| Subtitles: DVD (VobSub) pictures | `dvdsub.mkv` | VLC | Plays |

Options that aren't about a file format, checked by their own tests:

| Feature | How it was checked | Result |
| --- | --- | --- |
| Subtitle font, colour, outline, background, height; text encoding | Snapshot of the Subtitle Style page; VLC restarts at the same place with the same tracks | Passes: a style becomes VLC’s text renderer options, and VLC restarts at the same place with the same tracks (`twoSubtitlesSurviveANewStyle`) |
| Two subtitle tracks at once (VLC) | Two tracks selected in `subtitles.mkv` | Passes: English with French under it, still there after a restart |
| Turn, flip, zoom | `PictureGeometryTests`: a quarter turn lays the picture out sideways; Linux tests of the maths | Passes |
| Deinterlacing methods | libVLC's filter names, set while playing `mpeg2-ac3.ts` | Passes |
| 360° video | A generated MP4 with an `sv3d` box goes to VLC, which reports it spherical; looking around moves the viewpoint | Passes |
| Volume boost to 200% | `LoudnessPlaybackTests` | Passes |
| ReplayGain (Sound Check) | `tone-replaygain.flac`: track −6 dB, album −4 dB | Passes |
| Per-file memory | `TrackChoiceTests`: tracks, timing and a turn come back | Passes |
| Preferred audio and subtitle languages | `TrackChoiceTests`: French picked in `two-audio-tracks.mkv` and `subtitles.mkv` | Passes |
| Titles, DVD menus | `DiscPlaybackTests`: a VIDEO_TS folder and an ISO are recognised as a DVD; the menu, Select, title list and resume tests wait for a VLCKit with disc support | Recognised; menus and titles wait for a VLCKit with disc support (deviation 4) |
| Subtitle search (OpenSubtitles) | Stubbed replies: search by hash and title, sign in, download, quota errors | Passes |
| Jump to time | Already there (⌘J, Tools ▸ Go To) | Done |

### What was built

**Subtitles**
- **Style:** font (five families every Apple device has), colour, bold, outline, background (none, see-through, solid) and height. Options ▸ Subtitles ▸ Style, remembered between launches.
- **Text encoding** for subtitle files that aren't Unicode: 18 character sets, as VLC's "Default encoding" offers them.
- VLC reads both when it starts, so changing one restarts the video at the same place, with the same tracks. AVFoundation applies the style straight away.
- **A second subtitle track** under the first (VLC), for learning a language.

**Picture**
- **Turn** 90° at a time, and **flip** either way: the player's view does it, so both engines can (Video ▸ Turn and Flip, and Options ▸ Picture).
- **Zoom** up to 4×: pinch past Fill, or Video ▸ Zoom In (⌘=) and Zoom Out (⌘−); drag to move around. Whole Picture (⌘0) goes back.
- **Deinterlacing method,** as in VLC: Yadif, Yadif (2×), Blend, Bob, Linear, Mean, Discard, X, Phosphor and Film NTSC (IVTC), each with a line on what it's good for.
- **360° video:** files with the spherical metadata phones and cameras write (Google's `sv3d`, Apple's `prji`, the older XML) play with VLC. Drag to look around, pinch to zoom, and Look Straight Ahead resets.

**Sound**
- **Volume Boost** (Settings ▸ Playback ▸ Listening) lets the volume go to 200%: ↑ past 100% on the Mac, or the volume slider. Above 100%, playback moves to VLC.
- **Sound Check** (Listening too) levels music with ReplayGain, by track or album, with a level and protection from clipping. Tags are read from FLAC, Ogg, Opus, MP3, APE and MP4 files (R128 too).

**Remembered per file, and your languages**
- The next time a video plays, the audio and subtitle tracks, timing, shape, crop, turn and deinterlacing you chose come back (the last 500 files). Settings ▸ Playback ▸ Languages ▸ Remember Options for Each File turns it off.
- **Languages** (same place): audio in your language when the file has it, and subtitles Automatic, When the Audio Is in Another Language, Always, or Off, in a language you pick.

**Discs** (titles, menus, images): built, but switched off until VLCKit plays discs (deviation 4)
- **DVD and Blu-ray folders and images** open as the disc: File ▸ Open a folder holding VIDEO_TS or BDMV (or VIDEO_TS itself, an IFO file in it, or an `.iso`), or drag one onto the window. Today the player says it can't play discs yet.
- **In a menu** the player shows a remote (the arrows around Select) at the bottom, out of the menu's way. The keyboard's arrows and Return work it too.
- **Titles:** Options ▸ Disc lists them with their lengths and chapters and marks the main feature; Go to Disc Menu (and Pop-Up Menu for Blu-ray). Playback ▸ Title and Disc Menu on the Mac, and VLC's keys: Shift-M menu, Shift-B/Shift-O next and previous title, Shift-N/Shift-P chapters.
- **In the library** a disc folder or image is one movie, not a pile of VOB files. Its length, picture, sound and subtitle languages come from the disc's own files, and `poster.jpg` and `movie.nfo` from inside the folder.
- **Resume** skips the menu: the film starts where you left it. Progress is saved only while the film plays, not menus or extras.

**Playlists**
- M3U and M3U8, PLS, XSPF and cue sheets open as the list they hold. A cue sheet's tracks play as stretches of one file, running on into each other without a gap.

**Subtitle search**
- **OpenSubtitles.com** with your own API key (Settings ▸ Metadata on the Mac, Settings on iPhone and iPad; kept in the Keychain, with an optional account for more downloads).
- Subtitles ▸ Search OpenSubtitles: matches made for your exact file come first (by its hash), then by title, or show, season and episode. Machine-translated ones go last.

### How it was checked

- **Builds:** macOS and the iOS Simulator build cleanly (Xcode, Swift 6 language mode).
- **Tests on the Mac:** 313 package tests pass, including the parity suite above (31 samples played through the app's own controller, each on the engine the router should pick, with the tracks, chapters and subtitles each engine reports) and real-media tests for two subtitle tracks, a new subtitle style restarting VLC in place, turning and zoom, 360° video, Sound Check and the volume boost, and remembered options.
- **Tests on Linux:** 250 tests of the pure logic (disc readers, playlist files, loudness, track preferences, geometry, tag readers).
- **Snapshots:** the Options pages and the redesigned music lists are drawn to PNG files (`build/snapshots`) and were checked by eye.
- **Not yet checked by hand:** an iPhone run, and real discs (see deviation 4).

### Stubbed or deferred

- **Blu-ray menus** need VLCKit's libbluray and an unencrypted disc. Java (BD-J) menus need a Java runtime that VLCKit doesn't have, so those discs play their titles without menus.
- **Physical discs:** Macs rarely have a drive now. An external drive's disc mounts as a folder, which plays like any DVD folder.
- **Audio CDs and Video CDs** aren't supported.
- **Volume normalisation** for files without ReplayGain (see below).

### Where this deviates from the build prompt, and why

1. **No volume normaliser.** libVLC 4 gives a player's audio filter to its equalizer (`libvlc_media_player_set_equalizer` replaces it), so VLC's "normvol" can't be switched on from the app. Sound Check levels music that has ReplayGain tags instead.
2. **Subtitle search needs your OpenSubtitles key,** as lookups use your own keys. Without one, Search OpenSubtitles doesn't appear.
3. **In a disc's menu, the arrow keys move around the menu** instead of skipping and changing the volume, as on a DVD player and in VLC.
4. **DVDs and Blu-rays don't play yet.** The official VLCKit 4.0.0a25 binaries are configured with `--disable-dvdread --disable-dvdnav --disable-bluray --disable-vcd`: a VIDEO_TS folder ends at once and an image fails to open. Coreplay recognises the disc and says it can't play it, keeps listing its VOB and M2TS files (which do play), and skips `.iso` files in the library. Titles, menus, the remote, resume and library support are written and tested where they can be (the IFO and MPLS readers on Linux); `DiscLayout.canPlayDiscs` turns them on with a VLCKit built with libdvdnav and libbluray.

---

## Music lists as charts — October 14, 2026

You said the music lists looked like plain lists. They now look like the charts in Music and Spotify.

- **Songs:** a header with the count, total time, Play and Shuffle; **Top Songs**, your ten most played, numbered like a chart in two columns; then every song as a row with its artwork, a bold title over the artist, the album in its own column when the window is wide, and the length. Rows alternate with a faint stripe, light up under the pointer (a play button replaces the number) and show a moving waveform while they play. Lossless files carry a small LOSSLESS mark beside the title.
- **Album page:** on the Mac and iPad the cover sits beside the title, artist (a link to their page), year, genre and length, over a soft wash of the cover's colours; the iPhone keeps the stacked layout. Tracks are numbered chart rows.
- **Genres:** coloured tiles, each with a couple of its album covers tipped into the corner; the same genre always gets the same colours.
- **Artists:** a grid of round portraits with "2 albums · 18 songs" under each name. An artist's page lists their songs as numbered chart rows.
- Checked with snapshots of every piece (`music-*.png` in `build/snapshots`), in dark and light.

---

## Fixes after your first look at the hero — October 14, 2026

What you reported, and what changed.

**1. Pictures stretched tall, in the hero and in Continue Watching**
- **Cause:** VLC's thumbnailer scales a frame to exactly the box it's given, and Coreplay gave it the same box for every film. A 2.39:1 film was squeezed into it, so it looked stretched tall. Frames from MP4 and MOV files (made by AVFoundation) were fine; MKV, AVI, WebM and the rest were affected.
- **Fix:** VLC now reads the video's real shape first, pixel aspect included, and makes the frame in a box of that shape. When the shape can't be read, the frame is cropped to 16:9 instead of stretched.
- **Your library:** frames already taken from those files are taken again once, by themselves, the next time the library starts. Scrubber previews are remade too.

**2. The carousel didn't move on, and swiping wasn't smooth**
- It held still whenever the pointer was over it, which on the Mac is most of the time. Now it moves on every eight seconds. It pauses only off screen, in the background, with Reduce Motion, or while a video plays.
- It was a scroll view of full-size pages. It's now a pager that draws only the current page: pictures cross-fade and the words slide in. While you swipe, the words follow your finger.
- A clip holds its page until it ends, plus three seconds. If no picture arrives within eight seconds, it gives up and the page moves on.

**3. Music had no hero**
- Albums (Mac and iPad) and the Music tab (iPhone) now open with a carousel of albums: the cover, sharp, over a blur of itself, "Album · Artist · Genre · Year", "9 songs, 32 min", **Play** and **Shuffle**.
- Albums you've played lately and new ones come first.
- Home's carousel includes two albums among the films and shows.

**4. The crash when playing a movie**
- **Likely cause:** the carousel's clip and the movie drawing through VLC at the same time. Two libVLC video outputs at once trip libVLC's OpenGL checks, which end the app in VLCKit's development builds (the test suites were already arranged to avoid this). A clip could start in the second between pressing Play and the movie appearing.
- **Fix:**
  - the player stops any clip, and waits for its picture to go, before it opens anything;
  - a clip never uses VLC while the player has a video open, even paused;
  - the carousel checks again just before a clip starts.
- **New tests:**
  - a clip and the movie together;
  - VLC's view taken out of its window while it plays.
  Neither crashes.

**5. The movie page**
- **The backdrop:** the movie's wide picture fills the page behind everything, as on Netflix and in the TV app, shaded at the left and the bottom. It's the backdrop, your chosen artwork or a frame; with none of those, the poster blurred.
- **Over it:**
  - "MOVIE", the title, the details line and badges;
  - **Play** or **Resume** (with progress), then Play from Beginning, watchlist, watched and •••, and time left;
  - the synopsis with **More**, and who's in it and who directed it.
- **Scrolling:** the cast and the Information section follow, and the picture darkens as you go.
- The series page now uses the same full-page picture.

## Hero carousel and series page — October 13, 2026

Built during Milestone 6, at your request (with the TV app's Home and show
page as the reference).

### What was built

**The hero carousel** (Home, then Movies and TV Shows)
- **Full artwork:**
  - on the iPad and the Mac it runs edge to edge under the toolbar;
  - on the iPhone it's a tall card under the large title.
  The bottom fades into the page, so it ends softly in light and dark appearance.
- **Each page shows:**
  - a "New" or "New Episodes" badge;
  - the title, set large and compressed (in place of a film's title art);
  - "Movie · Drama, Mystery · 2024 · 2 hr 4 min" or "TV Show · Comedy · 2 Seasons";
  - a three-line synopsis;
  - the white Play capsule ("Play", "Resume", "Resume S1, E5", "Play First Episode"), with a progress line when started;
  - "+" for the watchlist.
- **Moving between pages:**
  - page dots;
  - arrows that appear on hover on the Mac and stay visible on the iPad;
  - swiping.
  It moves on by itself every eight seconds, but not while it's off screen, while the app is in the background or while a video plays. With Reduce Motion on, it doesn't move on by itself. (Until October 14 it also held still under the pointer; see the fixes below.)
- **What it features** (`FeaturedPicker`, tested):
  1. up to three titles added in the last two weeks;
  2. up to two titles you're in the middle of;
  3. then a pick of unwatched titles that changes once a day.
  Real backdrops come before frames, and titles with no picture are used only when there's nothing else.
- **Movie clips:**
  - 1.6 seconds after a movie's page settles, 30 seconds of the movie itself play behind the title. They start about a sixth of the way in, past the opening credits and before any spoilers.
  - The clip fades in over the artwork once frames arrive, and back out at the end.
  - It's silent, with a mute button to turn the sound on.
  - It uses the same engines as the player, so MKV and AVI clips play too.
- **When clips don't play:**
  - while something else is playing, or while the player has a video open (even paused);
  - in Low Power Mode;
  - with iOS's Auto-Play Video Previews turned off;
  - with Settings ▸ Playback ▸ Play Previews turned off.
  A silent clip never interrupts music from another app: it opens no audio output, and on iOS uses the ambient audio category.
- **The watchlist:** "+" adds a movie or show; a Watchlist row on Home lists them. Movie and show menus have Add to and Remove from Watchlist too.

**The series page**
- **Header:**
  - the backdrop, the title, "TV Show · Comedy, Drama";
  - the synopsis with **More**;
  - year, seasons, rating and network;
  - 4K/HDR/Atmos/5.1/CC badges from the episode you'd play next;
  - **Starring** on the right.
- **One button carries on:** "Resume S1, E5" (with its progress and time left), "Play S1, E6" after a finished episode, or "Play First Episode".
- **A season menu** ("Season 1 ⌃⌄") over a row of wide episode cards. Each card has:
  - the still, with a progress bar and a watched check;
  - EPISODE 5, the title and a three-line synopsis;
  - "▶ 45 min" or "▶ 23 min left";
  - a ••• menu (Resume, Play from Beginning, watched, Edit Info…).
- **The episode you're up to** is outlined and tagged CONTINUE or UP NEXT. The row opens scrolled to it, in its season.
- **Below:** the cast, and an About section with the full synopsis and details.

**Carrying on to the next episode** (in the player)
- **When the card appears:** where the end credits start (a chapter named like "End Credits", "Credits" or "Outro"), or 20 seconds before the end when there's no such chapter.
- **The card** shows the next episode's still, a countdown ring, its title, **Play Now** and **Watch Credits**.
- **The countdown:**
  - at a credits chapter, the next episode starts after ten seconds;
  - without one, it counts down to the end, so nothing of the story is cut off.
- **Settings ▸ Playback ▸ Play Next Episode Automatically** (on by default). Turned off, the player stops on the last frame and the card waits for you.
- **Watched:** an episode left at its end credits counts as watched, even when the credits start before 92%. This keeps it out of Continue Watching.

**Also fixed** (from the Milestone 6 parity run)
- **FLAC and AIFF files** played with AVFoundation listed no audio track (they have no selection group). Their tracks are now read from the file.
- **MP4 subtitles** listed twice ("English" and "English (Forced)"). AVFoundation adds a forced-only twin of each subtitle track and picks it by itself, so the twin is no longer listed.

### How it was checked

- **Mac and iOS Simulator builds:** pass.
- **The full test run:** passes, including the parity suite, which now passes for every sample.
- **New tests:**
  - `UpNextPolicy`: credits chapters, countdowns, autoplay off, short clips;
  - `FeaturedPicker`: order, limits, daily rotation;
  - watched-at-the-credits rules;
  - what the carousel features from a made-up library (badges, button titles, lines);
  - the watchlist;
  - clip start points.
- **Snapshots in `build/snapshots`,** checked by eye:
  - `hero-wide-movie`, `hero-wide-show`, light and dark;
  - `hero-card` (iPhone);
  - `show-page`, light, dark and compact;
  - `up-next-card`.

### Stubbed or deferred

- **Title art:** the hero sets the title in type. TMDB's logo images could replace it later, but that needs a library schema change.
- **Clips** come from the file itself, about a sixth of the way in. There are no trailers.
- **Still to check by hand on the Mac and an iPhone:**
  - the carousel's paging, the clip fading in, and mute;
  - Up Next at a real episode's credits.
  Snapshots can't show scrolling, video or Liquid Glass.

### Where this deviates, and why

- **"+" adds to Coreplay's own watchlist.** It has no TV app account behind it, so the list stays on this device for now. The plan's iCloud sync (Milestone 8) can carry it.

---

## Milestone 5: Video player polish — October 13, 2026

### What was built

**The video player, redesigned** (your request for native controls that aren't boxy)
- **Chrome-free by default.** Tap, or move the pointer on the Mac, to show the controls. They hide after three seconds of playing.
- **Liquid Glass, as in iOS 26:**
  - round glass buttons for Back and Picture in Picture;
  - a glass capsule at the top right with AirPlay (plus volume and full screen on the Mac);
  - a glass capsule at the bottom right with speed, audio and subtitles, and ••• for everything else.
- **Plain transport in the middle,** as in the TV app: back 10 seconds, play/pause, forward 10 seconds, with a soft shadow so they read over bright video. No boxes or bezels.
- **Room around every symbol.** Buttons are 44 points on iPhone and iPad and 40 on the Mac, around 17-point symbols, so nothing is squeezed (the subtitle button was).
- **The title** sits above the scrubber, with a line of details and a 4K or HD badge.
- **Short confirmations** appear over the video, such as "Speed 1.5×", "Subtitles: English" and "Saved to Pictures".
- **Pinch** on iPhone and iPad switches between fit and fill.
- **AirPlay:** while a video plays on an Apple TV, the player says so instead of showing black.

**Frame previews while scrubbing** (your YouTube-style request)
- Drag the scrubber, or hover over it on the Mac, to see the frame at that point with the chapter name and time.
- Chapters show as small gaps in the scrubber.
- **How the frames are made:**
  - once a local video has played for two seconds, up to 200 small frames (at least two seconds apart) are made in the background;
  - they're made coarse to fine, so a nearby frame is ready almost at once and the rest fill in while you watch;
  - frames you scrub to are made next;
  - AVFoundation makes them for MP4 and MOV, and VLC's thumbnailer for everything else.
- Finished sets are kept in Caches (trimmed to 300 MB, oldest first), so a video you watch again previews at once.

**Every Level 2 option, inside the player** (your request)
- **Where:** ••• opens a glass panel over the video. It sits beside the video on wide screens and rises from the bottom on iPhone in portrait. Tapping outside closes it. Now Playing's ••• opens the same panel for music.
- **Audio:**
  - the language, with the track's own name when the file has one ("English · Commentary · Stereo");
  - audio timing;
  - channels: stereo, mono, left or right only, swapped, or Dolby Surround.
- **Subtitles:** the language, Add Subtitle File, subtitle timing, and text size.
- **Speed:** 0.25× to 4×, with speech kept at its natural pitch.
- **Picture:**
  - fit or fill, the shape (16:9, 4:3, 2.39:1 and others) and crop;
  - colours (brightness, contrast, saturation, hue and gamma);
  - deinterlacing.
- **Sound:** a 10-band equalizer with libVLC's 18 presets and a preamp. It's remembered between launches, as is the subtitle size.
- **Chapters** to jump to.
- **Tools:**
  - A–B loop;
  - frame by frame;
  - Save Picture, to Photos on iPhone and iPad or the Pictures folder on the Mac;
  - Go To a typed time ("1:02:03", "45m").
- **Now Playing:**
  - which engine is playing, and why;
  - a switch to the other engine when it can open the file;
  - the resolution, length, audio format and file.
- **Engine hand-off:** options AVFoundation can't do move playback to VLC at the same position, as timing already did. These are shape, crop, colours, deinterlacing, channels, the equalizer and subtitle size.

**Picture in Picture and AirPlay**
- **Both engines:** AVFoundation uses Apple's PiP controller. VLC uses VLCKit 4's PiP support, fed by the player's own video view.
- **Going home on iPhone and iPad:** AVFoundation video moves into PiP by itself.
- **The player and PiP:** the player closes while PiP is on and comes back when you return from PiP.
- **Screen sleep on iPhone and iPad:** the screen stays on while video plays, but not in PiP, when you're using other apps.
- **AirPlay:** buttons in the player (video devices first) and in Now Playing. AVFoundation video plays on the Apple TV itself.

**The Mac**
- **Menus:**
  - Playback: Jump to Time ⌘J, Chapters, Speed and the A–B loop;
  - Audio: the track, volume, timing, Channels and Equalizer;
  - Video: Size, Shape, Crop, Deinterlacing, Reset Colours, Next and Previous Frame (⌃⌘→, ⌃⌘←), Save Picture ⌥⌘S, Picture in Picture ⌃⌘P and Float on Top;
  - Subtitles: the track, Add File, timing and Text Size.
- **Keys in the player, following VLC** (all but ↑ ↓ work on an iPad with a keyboard too):

  | Key | Action |
  | --- | --- |
  | Space | Play or pause |
  | ← → | Skip 10 seconds (with ⌥, a minute) |
  | ↑ ↓ | Volume |
  | F | Full screen |
  | M | Mute |
  | Esc | Close the options panel, leave full screen, or go back to the library |
  | [ ] (or - +) | Slower and faster |
  | = | Normal speed |
  | , . | Frame by frame |
  | B, V | Cycle audio tracks and subtitles |
  | G H | Subtitle timing |
  | J K | Audio timing |
  | Shift-L | A–B loop |
  | Shift-S | Save Picture |
  | P | Picture in Picture |
  | I | Options |
- **Float on Top** keeps the window above others.
- **The Dock menu** shows what's playing, with Play/Pause, Next, Previous and Show Video.
- **Display sleep:** the display stays awake while video plays.

**Artwork and details without a TMDB key** (your request)
- **TV shows come from TVmaze:** posters, synopses and cast, plus episode titles, synopses, air dates and stills.
- **Movies come from Wikipedia and Wikidata:** the poster from the film's article, its opening paragraph as the synopsis, the year, and the IMDb ID.
- **When they run:** automatically after scans, with nothing to set up. Settings ▸ Metadata ▸ Free Sources turns them off and has Look Up Again. Fix Match searches them too.
- **With a TMDB key,** TMDB is used instead and replaces their details and artwork. Posters beside your files and artwork you chose are kept.
- **Credits:** movie and show pages credit TVmaze or Wikipedia, as their licences (CC BY-SA) ask.
- **Not used:** the iTunes Search API, because its terms only allow promoting iTunes content.

**Now Playing (music)**
- It has the same glass header buttons, plain transport and capsule volume as the video player.
- ••• opens the options panel: speed, sound, audio tracks and Now Playing.
- The narrow Mac layout keeps the title at full size.
- The Mac playback bar's volume is a mute button and a capsule slider.

### How it was checked
- **Linux:** 158 Swift Testing tests pass. New ones cover:
  - picture shapes, colour limits, the equalizer, subtitle sizes and the A–B loop;
  - the order frame previews are made in, and finding the nearest frame;
  - times typed into Go To;
  - TVmaze and Wikipedia requests, responses and matching;
  - track names.
- **Mac, through `Tools/build-check.sh` with Xcode 26.4.1:**
  - the Mac and iOS Simulator builds have no warnings;
  - all 180 tests pass;
  - new: lookups without a key, against stubbed TVmaze and Wikipedia replies.
- **Snapshot tests** draw the player screens to `build/snapshots`:
  - the video player and its top controls, every options page, Now Playing wide and narrow, the playback bar and the scrubber;
  - I checked them for layout and spacing, and fixed what they showed. The Equalizer switch's row was too narrow on the Mac, the narrow Now Playing shrank the title, preset names had mixed capitals, and commentary tracks lost their names;
  - they can't show the video, AirPlay buttons, text fields, Mac switches or real Liquid Glass.
- **Not yet tested:**
  - Picture in Picture with real videos, on either engine;
  - frame previews and lookups without a key, with your files;
  - AirPlay;
  - anything on iPhone or iPad.

**Fixed after this report: VLC movies stuck on "loading"** (you found it)
- **The cause:** a deadlock. When a video started, the engine applied the picture options again on the main thread. Each one waits for the video output's lock. libVLC holds that lock while it creates the output, and creating it waits for the main thread to set up its view. A sample of the stuck process showed exactly that.
- **The fix:**
  - option changes now reach libVLC on a background queue, never the main thread;
  - when a video starts, only the options you changed are applied again, so a plain movie doesn't touch the video output at all;
  - Picture in Picture only updates VLC's window while it's showing.
- **New playback tests** (PlaybackEngineTests) play a generated movie through both engines in a small window:
  - VLC plays three times after AVFoundation, the order that froze;
  - one run sets every option while the video opens;
  - if anything locks up, a watchdog samples every thread into `build/hang-<test>.txt` and ends the run, so the build script can't hang;
  - all 184 tests pass.

**Fixed after this report: scrub previews showed a nearby frame, not the one playback lands on** (you found it)
- **The cause:** the preview showed the nearest frame of the background strip. Strip frames are up to half a slot apart (18 seconds in a two-hour film), and each was only near its slot's time (the closest keyframe), so the frame you saw could be well away from where a click took you.
- **The fix:**
  - once the pointer or thumb rests for 0.12 seconds, the frame at exactly that time is made (decoded from the keyframe before it) and replaces the strip's frame;
  - the 32 most recent exact frames are kept, so going back to a spot is instant;
  - VLC makes its frames with hardware decoding, so exact frames from 4K files take a fraction of a second rather than several;
  - strip frames now sit within a second of their slot's time (they could be half a slot off).
- **Tests** read the frame's time back from the test movie's moving bar: AVFoundation, VLC and the resting-pointer preview all land within one frame of the time asked for. All 187 tests pass.

### Stubbed or deferred
- **Milestone 6 (VLC parity):**
  - subtitle style beyond size (font, colour, outline, background, position, text encoding, two tracks at once);
  - zoom, rotate and flip;
  - 360° video;
  - deinterlacing modes;
  - volume boost, normalisation and ReplayGain;
  - DVD menus;
  - bitrate, frame rate and sample rate in Now Playing;
  - remembering options per file.
- **VLC video when you go home on iPhone:** it pauses unless PiP is already on. Starting PiP for it automatically needs testing on a device. VLC's PiP on the Mac depends on VLCKit 4's alpha and needs checking too.
- **VLC-only formats on an Apple TV:** they play their sound over AirPlay, but the picture needs screen mirroring for now. Sending the picture to an external display, as VLC for iOS does, comes with Chromecast in Milestone 7.
- **Frame previews** are made for local files only. Network streams come in Milestone 7.
- **iPad multiple windows** stay off, and landscape-first video on iPhone isn't done. Milestone 1 placed both here; they move to Milestone 9.

### Where this deviates from the build prompt, and why
1. **There are no separate player windows.** Video plays in the main window, as you asked. Float on Top floats that window.
2. **Free sources look titles up without a key, and they're on by default.** The prompt says lookups are opt-in and use your own keys. You asked for artwork found from names automatically. Your video titles are sent to TVmaze and Wikipedia; Settings ▸ Metadata ▸ Free Sources turns this off.
3. **Frame previews are separate small JPEGs, not sprite sheets.** They're made coarse to fine and shown as they arrive, then saved as one file per video.
4. **The equalizer arrived early** (it was planned for Milestone 8). It's a page of the options panel, reached from both players, rather than its own sheet.
5. **Speed is a menu and a panel page**, not a long press on the speed button. A long press is hard to discover and doesn't exist with a mouse.

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
- Many film posters on Wikipedia are non-free images used there under fair use. Fine for a personal library; before a public release, drop Wikipedia posters or use another source.

### Running it
1. Open `Coreplay.xcodeproj` in Xcode 26 or later.
2. Set `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`, or choose a team under Signing & Capabilities.
3. Let Swift Package Manager download VLCKit. It's large.
4. Run the **Coreplay** scheme on **My Mac** or an iPhone simulator. ⌘U runs the tests.
5. From Terminal, `bash Tools/build-check.sh` builds both platforms and runs the tests, with logs in `build/`.
