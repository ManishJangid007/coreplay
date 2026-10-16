# Coreplay

A free, open-source media player for the Mac that plays almost anything.

Coreplay plays the files other players give up on (MKV, AVI, FLAC, Opus,
DTS, TrueHD and many more) using VLC's playback engine. It also turns your
music and video folders into a library that looks and feels like Apple Music
and the Apple TV app: albums with cover art, movies with posters, TV shows
sorted into seasons, and everything picks up where you left off.

There's no account, no ads and no tracking.

## Download

**[Download the latest version](https://github.com/ManishJangid007/coreplay/releases/latest)**
(the `.dmg` file under **Assets**).

You need **macOS 26 Tahoe or later**, on an Apple silicon or Intel Mac.

There's no iPhone or iPad download yet. You can build the app for them
yourself (see [Build from source](#build-from-source)).

## Install

1. Open the downloaded `.dmg` file.
2. Drag **Coreplay** onto the **Applications** folder.
3. Open Coreplay from your Applications folder or Launchpad.

**The first time you open it**, macOS says it can't verify Coreplay. This is
expected. The app isn't notarized: that needs a paid Apple Developer
membership, which this free project doesn't have. To open it anyway:

1. Click **Done** in the warning.
2. Open **System Settings ▸ Privacy & Security**.
3. Scroll down to the message that says Coreplay was blocked, and click
   **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open Anyway** again.

You only need to do this once. If you're comfortable with Terminal, this
command does the same thing:

```sh
xattr -dr com.apple.quarantine /Applications/Coreplay.app
```

## Getting started

**Your library.** Coreplay adds your **Music** and **Movies** folders on its
own. To add another folder (an external drive works too), choose
**File ▸ Add Folder to Library…** (⇧⌘O), or click **Add Folder…** on the
Home screen or in **Sources**. New files show up by themselves.

**Play a single file** without adding it to the library:

- choose **File ▸ Open…** (⌘O),
- drag the file onto the Coreplay window or its Dock icon, or
- right-click it in Finder and choose **Open With ▸ Coreplay**.

Folders and playlist files (M3U, PLS, XSPF and cue sheets) open the same way.

**Network.** Open **Sources** (under **Library** in the sidebar) to browse
shared folders on other computers and media servers. To play a stream,
choose **File ▸ Open Network Stream…** (⌘N).

**Posters and episode names.** Coreplay looks these up for you from TVmaze and
Wikipedia, with no setup. For better results, get a free API key from
[TMDB](https://www.themoviedb.org/settings/api) and paste it in
**Settings ▸ Metadata**.

### Name your files so Coreplay can sort them

| What | Name it like this |
| --- | --- |
| Movie | `Heat (1995).mkv` |
| TV episode | `Severance S01E02.mkv`, or `Severance/Season 1/02.mkv` |
| Music | Tags inside the file are used first. Otherwise `Artist/Album (Year)/01 Title.flac` |

Videos that don't look like a movie or an episode go under **Home Videos**.
If Coreplay picks the wrong movie or show, use **Fix Match** or **Edit Info**
on it. Your changes are kept, even when the folder is scanned again.

## What it can do

**Plays nearly everything**
- Uses Apple's own player for the formats Apple supports, and VLC for
  everything else. It switches by itself, so you don't have to think about it.
- 360° videos: drag to look around.

**Your library**
- Music by album, artist, genre and composer, with cover art.
- Movies, TV shows (by season and episode) and home videos, with posters,
  synopses and cast.
- Remembers where you stopped, marks what you've watched, and offers the next
  episode when the credits roll.
- Playlists and smart playlists. M3U, PLS and XSPF files import as playlists.

**Subtitles and audio**
- Subtitles inside the file or in a separate file, with your choice of font,
  size, colour and position. Two subtitle tracks at once, and timing you can
  adjust.
- Search OpenSubtitles.com from the player (needs your own free account).
- Equalizer, volume up to 200%, Sound Check, synced lyrics and a sleep timer.

**Picture**
- Change the shape, crop, zoom, rotate or flip the picture, fix interlaced
  video, and save a still to your Pictures folder.
- Picture in Picture and AirPlay.

**Network**
- Shared folders over SMB (Windows and Mac file sharing), FTP, SFTP, NFS and
  UPnP/DLNA media servers. Logins are kept in your Mac's Keychain.
- Streams: HTTP(S), HLS, MPEG-DASH, RTSP, RTMP, RTP/UDP, MMS and SRT.
- Send video to a Chromecast or a DLNA TV.

**On the Mac**
- Menu commands and keyboard shortcuts for everything (see below).
- Right-click the Dock icon for play/pause, next and previous.
- A desktop widget, and actions for Shortcuts and Siri.

## Privacy

Coreplay has no accounts, ads, analytics or tracking. Your files never leave
your Mac. It only goes online for these things:

- **Movie and show details**, from TMDB (only if you add a key), or TVmaze and
  Wikipedia otherwise. Turn the free sources off in
  **Settings ▸ Metadata ▸ Free Sources**.
- **Lyrics** from LRCLIB, only if you turn on **Look Up Lyrics** in Settings.
  It sends the song's title, artist, album and length.
- **Subtitles** from OpenSubtitles.com, only when you search for them.
- **Network shares and streams** that you open yourself.

## Known limitations

- **DVD and Blu-ray discs** don't play yet, because the VLC library Coreplay
  uses is built without disc support. The `.vob` and `.m2ts` video files on a
  disc play on their own.
- **iCloud sync** of play counts and playlists is off in the downloadable app.
  It needs a paid Apple Developer membership.
- **iPhone and iPad** builds are available from source only.
- Coreplay uses a pre-release of VLC's library (VLCKit 4), so an occasional
  crash is possible. Please [report it](https://github.com/ManishJangid007/coreplay/issues).
- Casting, Siri, Handoff and the widget have had the least testing so far.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open a file | ⌘O |
| Add a folder to the library | ⇧⌘O |
| Open a network stream | ⌘N |
| Play or pause | Space |
| Next / previous | ⌘→ / ⌘← |
| Skip forward / back 10 seconds | ⌥⌘→ / ⌥⌘← |
| Volume up / down | ⌘↑ / ⌘↓ |
| Jump to a time | ⌘J |
| Stop | ⌘. |
| Check for new files | ⌥⌘P |

The **Playback**, **Audio**, **Video** and **Subtitles** menus list the rest.

## Help

- **macOS says Coreplay can't be opened.** See [Install](#install).
- **A folder's files don't appear.** Choose **File ▸ Check for New Files**
  (⌥⌘P). For a folder outside Music and Movies, add it with
  **File ▸ Add Folder to Library…** so Coreplay is allowed to read it.
- **The wrong poster or title.** Use **Fix Match**, or **Edit Info** to type
  your own.
- **Something else.** [Open an issue](https://github.com/ManishJangid007/coreplay/issues)
  and say what you did, what you expected, and your macOS version.

## Build from source

You need a Mac with macOS 26 and **Xcode 26** or later, and an Apple ID added
in **Xcode ▸ Settings ▸ Accounts** (a free one is fine).

1. Clone the repository and open `Coreplay.xcodeproj`.
2. Set your team: put your Team ID in `Config/Base.xcconfig`
   (`DEVELOPMENT_TEAM = ABCDE12345`), or pick it under the Coreplay target ▸
   **Signing & Capabilities**. Change `BUNDLE_ID_PREFIX` there too.
3. Wait for Xcode to resolve packages. The first time, it downloads the
   official VLCKit 4.0.0a25 framework from VideoLAN (it's large).
4. Choose the **Coreplay** scheme and **My Mac**, an iPhone simulator or your
   iPhone, then click **Run**.

Apps installed on an iPhone with a free Apple ID stop opening after 7 days.
Run them from Xcode again to renew them.

From Terminal:

- `bash Tools/build-check.sh` builds for macOS and the iOS Simulator and runs
  the tests (⌘U in Xcode does the tests too). Logs go to `build/`.
- `bash Tools/make-dmg.sh` builds a Release copy of the Mac app and packs it
  into `build/Coreplay.dmg`.

How the code is organised, and how the library, playback and networking
work, is described in [`Docs/Architecture.md`](Docs/Architecture.md).
[`Docs/Milestones.md`](Docs/Milestones.md) records what was built when.

## Contributing

Bug reports and pull requests are welcome. Before you open a pull request,
run `bash Tools/build-check.sh` and make sure the builds and tests pass.

## License and credits

Coreplay is released under the [Apache License 2.0](LICENSE).

- Playback uses [VLCKit and libVLC](https://www.videolan.org/vlc/libvlc.html)
  by VideoLAN, under the LGPL 2.1 or later. Coreplay links the official,
  unmodified VLCKit framework. Its license and where to get its source code
  are in **Settings ▸ About ▸ Acknowledgements**.
- This product uses the TMDB API but is not endorsed or certified by TMDB.
- TV details come from [TVmaze](https://www.tvmaze.com) and movie details from
  [Wikipedia](https://www.wikipedia.org) and Wikidata. Text from TVmaze and
  Wikipedia is CC BY-SA, and is credited in the app where it appears.
- Lyrics come from [LRCLIB](https://lrclib.net), and subtitle search from
  [OpenSubtitles.com](https://www.opensubtitles.com).

Coreplay is an independent project. It isn't affiliated with or endorsed by
VideoLAN or Apple. VLC is a trademark of VideoLAN. Apple, Mac and macOS are
trademarks of Apple Inc.
