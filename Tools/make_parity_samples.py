#!/usr/bin/env python3
"""Builds Coreplay's VLC parity sample suite: small files covering the rows of
the build prompt's feature checklist, plus a manifest of what each contains.

The samples are committed (Tests/ParitySamples, a few megabytes), so this only
needs running to change or add one. It needs FFmpeg 6 with libx264, libx265,
libvpx, libsvtav1, libxvid, libtheora, libvorbis, libopus and libmp3lame, and
dvdauthor, spumux and genisoimage for the DVD:

  python3 Tools/make_parity_samples.py Tests/ParitySamples

PlaybackEngineTests/ParitySuiteTests.swift plays every sample and writes
build/parity-report.md.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "Tests/ParitySamples")
SECONDS = 3
SIZE = "320x180"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

work = tempfile.mkdtemp(prefix="parity-")


def run(*args, cwd=None, env=None):
    result = subprocess.run(list(args), cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(f"failed: {' '.join(args)}")
    return result.stdout


def ffmpeg(*args):
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args)


def video_input(seconds=SECONDS, size=SIZE, rate=25):
    return ["-f", "lavfi", "-i", f"testsrc2=size={size}:rate={rate}:duration={seconds}"]


def tone(frequency=440, seconds=SECONDS, rate=48000):
    return ["-f", "lavfi", "-i", f"sine=frequency={frequency}:sample_rate={rate}:duration={seconds}"]


def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


# Subtitle sources: two cues each.
SRT = "1\n00:00:00,500 --> 00:00:01,400\nHello from SubRip\n\n2\n00:00:01,600 --> 00:00:02,800\nSecond line\n"
VTT = "WEBVTT\n\n00:00.500 --> 00:01.400\nBonjour de WebVTT\n\n00:01.600 --> 00:02.800\nDeuxième ligne\n"
ASS = """[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Helvetica,16,&H0000FFFF,&H000000FF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,2,1,8,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:00:01.40,Default,,0,0,0,,{\\i1}Styled{\\i0} at the top
Dialogue: 0,0:00:01.60,0:00:02.80,Default,,0,0,0,,{\\c&H00FF00&}Green text
"""
for name, text in [("subs.srt", SRT), ("subs.vtt", VTT), ("subs.ass", ASS)]:
    write(os.path.join(work, name), text)
SUBS = {name: os.path.join(work, name) for name in ("subs.srt", "subs.vtt", "subs.ass")}

H264 = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "30", "-pix_fmt", "yuv420p"]
X265_QUIET = "log-level=error"

# file, expected engine, checklist rows it covers, ffmpeg arguments after the inputs
SAMPLES = []


def sample(file, engine, covers, inputs, args):
    SAMPLES.append(dict(file=file, engine=engine, covers=covers, inputs=inputs, args=args))


# Containers and codecs
sample("h264-aac.mp4", "avFoundation", ["Formats: H.264 and AAC in MP4"],
       video_input() + tone(),
       H264 + ["-c:a", "aac", "-b:a", "64k", "-metadata:s:a:0", "language=eng", "-movflags", "+faststart"])
sample("hevc-aac.mp4", "avFoundation", ["Formats: HEVC in MP4"],
       video_input() + tone(),
       ["-c:v", "libx265", "-preset", "fast", "-crf", "32", "-pix_fmt", "yuv420p", "-tag:v", "hvc1",
        "-x265-params", X265_QUIET, "-c:a", "aac", "-b:a", "64k"])
sample("hevc10-hdr10.mkv", "vlc", ["Formats: HEVC 10-bit, HDR10", "Audio: AC-3"],
       video_input() + tone(),
       ["-c:v", "libx265", "-preset", "fast", "-crf", "32", "-pix_fmt", "yuv420p10le",
        "-x265-params", "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:"
        "master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):"
        "max-cll=1000,400:hdr10=1:" + X265_QUIET,
        "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc",
        "-c:a", "ac3", "-b:a", "128k"])
sample("hevc10-hlg.mp4", "avFoundation", ["Formats: HEVC 10-bit, HLG"],
       video_input() + tone(),
       ["-c:v", "libx265", "-preset", "fast", "-crf", "32", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1",
        "-x265-params", "colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:" + X265_QUIET,
        "-color_primaries", "bt2020", "-color_trc", "arib-std-b67", "-colorspace", "bt2020nc",
        "-c:a", "aac", "-b:a", "64k"])
sample("vp9-opus.webm", "vlc", ["Formats: VP9 and Opus in WebM"],
       video_input() + tone(),
       ["-c:v", "libvpx-vp9", "-b:v", "150k", "-deadline", "realtime", "-cpu-used", "8",
        "-c:a", "libopus", "-b:a", "48k"])
sample("av1-opus.webm", "vlc", ["Formats: AV1"],
       video_input() + tone(),
       ["-c:v", "libsvtav1", "-preset", "12", "-crf", "50", "-c:a", "libopus", "-b:a", "48k"])
sample("vp8-vorbis.webm", "vlc", ["Formats: VP8 and Vorbis"],
       video_input() + tone(),
       ["-c:v", "libvpx", "-b:v", "150k", "-deadline", "realtime", "-cpu-used", "8",
        "-c:a", "libvorbis", "-q:a", "2"])
sample("xvid-mp3.avi", "vlc", ["Formats: MPEG-4 Part 2 (Xvid) and MP3 in AVI"],
       video_input() + tone(rate=44100),
       ["-c:v", "libxvid", "-q:v", "8", "-c:a", "libmp3lame", "-b:a", "64k"])
sample("mpeg2-ac3.ts", "vlc", ["Formats: MPEG-2 and AC-3 in MPEG-TS"],
       video_input() + tone(),
       ["-c:v", "mpeg2video", "-b:v", "300k", "-c:a", "ac3", "-b:a", "96k", "-f", "mpegts"])
sample("mpeg2-mp2.mpg", "vlc", ["Formats: MPEG-2 and MP2 in MPEG-PS"],
       video_input() + tone(),
       ["-c:v", "mpeg2video", "-b:v", "300k", "-c:a", "mp2", "-b:a", "96k", "-f", "mpeg"])
sample("theora-vorbis.ogv", "vlc", ["Formats: Theora in Ogg"],
       video_input() + tone(),
       ["-c:v", "libtheora", "-q:v", "4", "-c:a", "libvorbis", "-q:a", "2"])
sample("wmv2-wma.wmv", "vlc", ["Formats: WMV and WMA in ASF"],
       video_input() + tone(rate=44100),
       ["-c:v", "wmv2", "-b:v", "300k", "-c:a", "wmav2", "-b:a", "64k"])
sample("h264-aac.flv", "vlc", ["Formats: FLV"],
       video_input() + tone(rate=44100),
       H264 + ["-c:a", "aac", "-b:a", "64k", "-f", "flv"])
sample("prores-pcm.mov", "avFoundation", ["Formats: ProRes and PCM in QuickTime"],
       video_input() + tone(),
       ["-c:v", "prores_ks", "-profile:v", "0", "-c:a", "pcm_s16le"])
sample("mpeg4-aac.3gp", "avFoundation", ["Formats: 3GP"],
       video_input(size="176x144") + tone(rate=22050),
       ["-c:v", "mpeg4", "-q:v", "8", "-c:a", "aac", "-b:a", "32k", "-ac", "1"])
sample("h264-dts.mkv", "vlc", ["Audio: DTS"],
       video_input() + tone(),
       H264 + ["-c:a", "dca", "-strict", "-2", "-b:a", "768k"])
sample("h264-truehd.mkv", "vlc", ["Audio: Dolby TrueHD"],
       video_input() + tone(),
       H264 + ["-c:a", "truehd", "-strict", "-2"])
sample("h264-flac.mkv", "vlc", ["Audio: FLAC in Matroska"],
       video_input() + tone(),
       H264 + ["-c:a", "flac"])

# Tracks, subtitles, chapters
sample("two-audio-tracks.mkv", "vlc", ["Audio tracks: two languages, named tracks", "Audio: E-AC-3"],
       video_input() + tone(440) + tone(660),
       ["-map", "0:v", "-map", "1:a", "-map", "2:a"] + H264 +
       ["-c:a:0", "ac3", "-b:a:0", "128k", "-c:a:1", "eac3", "-b:a:1", "96k",
        "-metadata:s:a:0", "language=eng", "-metadata:s:a:0", "title=Main",
        "-metadata:s:a:1", "language=fre", "-metadata:s:a:1", "title=Commentary"])
sample("subtitles.mkv", "vlc", ["Subtitles: ASS with styling, SRT and WebVTT inside Matroska"],
       video_input() + tone() + ["-i", SUBS["subs.ass"], "-i", SUBS["subs.srt"], "-i", SUBS["subs.vtt"]],
       ["-map", "0:v", "-map", "1:a", "-map", "2", "-map", "3", "-map", "4"] + H264 +
       ["-c:a", "aac", "-b:a", "64k", "-c:s:0", "ass", "-c:s:1", "srt", "-c:s:2", "webvtt",
        "-metadata:s:s:0", "language=eng", "-metadata:s:s:0", "title=Styled",
        "-metadata:s:s:1", "language=eng", "-metadata:s:s:2", "language=fre"])
sample("mov-text.mp4", "avFoundation", ["Subtitles: 3GPP timed text in MP4"],
       video_input() + tone() + ["-i", SUBS["subs.srt"]],
       ["-map", "0:v", "-map", "1:a", "-map", "2"] + H264 +
       ["-c:a", "aac", "-b:a", "64k", "-c:s", "mov_text", "-metadata:s:s:0", "language=eng"])
sample("sidecar.mkv", "vlc", ["Subtitles: external SRT and WebVTT files"],
       video_input() + tone(),
       H264 + ["-c:a", "aac", "-b:a", "64k"])

chapters = os.path.join(work, "chapters.txt")
write(chapters, ";FFMETADATA1\n"
      "[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=2000\ntitle=Opening\n"
      "[CHAPTER]\nTIMEBASE=1/1000\nSTART=2000\nEND=4000\ntitle=Middle\n"
      "[CHAPTER]\nTIMEBASE=1/1000\nSTART=4000\nEND=6000\ntitle=Ending\n")
sample("chapters.mkv", "vlc", ["Navigation: chapters"],
       video_input(6) + tone(seconds=6) + ["-i", chapters],
       ["-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2"] + H264 +
       ["-c:a", "aac", "-b:a", "64k"])

# Audio only
sample("tone-replaygain.flac", "avFoundation", ["Audio: FLAC with ReplayGain tags"],
       tone(rate=44100),
       ["-c:a", "flac", "-metadata", "title=ReplayGain Tone", "-metadata", "REPLAYGAIN_TRACK_GAIN=-6.00 dB",
        "-metadata", "REPLAYGAIN_TRACK_PEAK=0.500000", "-metadata", "REPLAYGAIN_ALBUM_GAIN=-4.00 dB",
        "-metadata", "REPLAYGAIN_ALBUM_PEAK=0.600000"])
sample("tone.opus", "vlc", ["Audio: Opus"], tone(), ["-c:a", "libopus", "-b:a", "48k"])
sample("tone.ogg", "vlc", ["Audio: Vorbis"], tone(), ["-c:a", "libvorbis", "-q:a", "2"])
sample("tone-alac.m4a", "avFoundation", ["Audio: ALAC"], tone(rate=44100), ["-c:a", "alac"])
sample("tone.wma", "vlc", ["Audio: WMA"], tone(rate=44100), ["-c:a", "wmav2", "-b:a", "64k"])
sample("tone.mka", "vlc", ["Audio: E-AC-3 in Matroska audio"], tone(), ["-c:a", "eac3", "-b:a", "96k"])
sample("tone.aiff", "avFoundation", ["Audio: AIFF"], tone(rate=22050), ["-c:a", "pcm_s16be", "-ac", "1"])


def probe(path):
    data = json.loads(run("ffprobe", "-v", "error", "-print_format", "json", "-show_format",
                          "-show_streams", "-show_chapters", path))
    streams = []
    for stream in data.get("streams", []):
        kind = stream.get("codec_type")
        if kind not in ("video", "audio", "subtitle"):
            continue
        if kind == "video" and stream.get("disposition", {}).get("attached_pic"):
            continue
        tags = stream.get("tags", {})
        entry = {"kind": kind, "codec": stream.get("codec_name")}
        language = tags.get("language")
        if language and language != "und":
            entry["language"] = language
        if tags.get("title"):
            entry["title"] = tags["title"]
        if kind == "video":
            entry["width"] = stream.get("width")
            entry["height"] = stream.get("height")
            if stream.get("color_transfer"):
                entry["transfer"] = stream["color_transfer"]
            if stream.get("pix_fmt"):
                entry["pixelFormat"] = stream["pix_fmt"]
        if kind == "audio":
            entry["channels"] = stream.get("channels")
            entry["sampleRate"] = int(stream.get("sample_rate", 0))
        streams.append(entry)
    duration = float(data.get("format", {}).get("duration", 0) or 0)
    return dict(duration=round(duration, 2), streams=streams, chapters=len(data.get("chapters", [])))


def make_dvd():
    """A DVD with a one-button menu and two titles with DVD subtitles, as a
    VIDEO_TS folder and an ISO image. Also gives a Matroska file with the
    DVD (VobSub) subtitles."""
    dvd_work = os.path.join(work, "dvd")
    os.makedirs(dvd_work)
    for index, frequency in ((1, 440), (2, 660)):
        raw = os.path.join(dvd_work, f"title{index}.mpg")
        ffmpeg(*video_input(2, "720x480", 30), *tone(frequency, 2),
               "-target", "ntsc-dvd", "-b:v", "700k", "-maxrate", "1200k", "-r", "30000/1001",
               "-c:a", "ac3", "-b:a", "128k", raw)
        spu = os.path.join(dvd_work, f"title{index}-spu.xml")
        write(spu, f'<subpictures format="NTSC"><stream><textsub filename="{SUBS["subs.srt"]}" '
                   f'characterset="UTF-8" fontsize="28.0" font="{FONT}" horizontal-alignment="center" '
                   f'vertical-alignment="bottom" left-margin="60" right-margin="60" bottom-margin="40" '
                   f'subtitle-fps="29.97" movie-fps="29.97" movie-width="720" movie-height="480"/>'
                   f'</stream></subpictures>')
        with open(raw, "rb") as source, open(os.path.join(dvd_work, f"title{index}-subs.mpg"), "wb") as target:
            result = subprocess.run(["spumux", "-s0", spu], stdin=source, stdout=target, capture_output=False,
                                    stderr=subprocess.PIPE)
            if result.returncode != 0:
                sys.stderr.write(result.stderr.decode())
                raise SystemExit("spumux failed")

    # Menu: a still background with one highlighted button.
    background = os.path.join(dvd_work, "menu-bg.png")
    ffmpeg("-f", "lavfi", "-i", "color=c=0x203060:size=720x480:duration=1",
           "-vf", "drawbox=x=260:y=200:w=200:h=80:color=white@0.9:t=fill,"
                  "drawtext=fontfile=" + FONT + ":text=Play:x=320:y=225:fontsize=32:fontcolor=black",
           "-frames:v", "1", background)
    highlight = os.path.join(dvd_work, "menu-hl.png")
    ffmpeg("-f", "lavfi", "-i", "color=c=black@0.0:size=720x480,format=rgba",
           "-vf", "drawbox=x=250:y=190:w=220:h=100:color=yellow@1.0:t=6",
           "-frames:v", "1", highlight)
    menu_raw = os.path.join(dvd_work, "menu.mpg")
    ffmpeg("-loop", "1", "-i", background, *tone(330, 2), "-t", "2",
           "-target", "ntsc-dvd", "-b:v", "1000k", "-r", "30000/1001", "-c:a", "ac3", "-b:a", "128k",
           "-aspect", "4:3", menu_raw)
    menu_xml = os.path.join(dvd_work, "menu-spu.xml")
    write(menu_xml, f'<subpictures format="NTSC"><stream><spu start="00:00:00.00" end="00:00:00.00" '
                    f'highlight="{highlight}" force="yes" autooutline="infer" outlinewidth="6" '
                    f'autoorder="rows"/></stream></subpictures>')
    with open(menu_raw, "rb") as source, open(os.path.join(dvd_work, "menu-buttons.mpg"), "wb") as target:
        result = subprocess.run(["spumux", menu_xml], stdin=source, stdout=target, stderr=subprocess.PIPE)
        if result.returncode != 0:
            sys.stderr.write(result.stderr.decode())
            raise SystemExit("spumux (menu) failed")

    author = os.path.join(dvd_work, "dvd.xml")
    folder = os.path.join(OUT, "dvd")
    shutil.rmtree(folder, ignore_errors=True)
    write(author, f'''<dvdauthor dest="{folder}">
  <vmgm>
    <menus>
      <pgc entry="title">
        <button>jump title 1;</button>
        <vob file="{os.path.join(dvd_work, "menu-buttons.mpg")}" pause="inf"/>
      </pgc>
    </menus>
  </vmgm>
  <titleset>
    <titles>
      <subpicture lang="en"/>
      <pgc>
        <vob file="{os.path.join(dvd_work, "title1-subs.mpg")}"/>
        <post>jump title 2;</post>
      </pgc>
      <pgc>
        <vob file="{os.path.join(dvd_work, "title2-subs.mpg")}"/>
        <post>call vmgm menu;</post>
      </pgc>
    </titles>
  </titleset>
</dvdauthor>
''')
    env = dict(os.environ, VIDEO_FORMAT="NTSC")
    run("dvdauthor", "-x", author, env=env)
    run("genisoimage", "-quiet", "-dvd-video", "-V", "PARITY_DVD", "-o", os.path.join(OUT, "dvd.iso"), folder)

    # DVD (VobSub) subtitles in Matroska.
    ffmpeg("-i", os.path.join(dvd_work, "title1-subs.mpg"), "-map", "0:v", "-map", "0:a", "-map", "0:s",
           "-c:v", "libx264", "-preset", "veryfast", "-crf", "34", "-vf", "scale=320:-2",
           "-c:a", "aac", "-b:a", "64k", "-c:s", "copy", "-metadata:s:s:0", "language=eng",
           os.path.join(OUT, "dvdsub.mkv"))


def make_playlists():
    album = os.path.join(OUT, "album.flac")
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=330:sample_rate=44100:duration=3",
           "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=3",
           "-f", "lavfi", "-i", "sine=frequency=550:sample_rate=44100:duration=3",
           "-filter_complex", "[0][1][2]concat=n=3:v=0:a=1", "-c:a", "flac",
           "-metadata", "artist=Parity", "-metadata", "album=Cue Sheet", album)
    write(os.path.join(OUT, "album.cue"),
          'PERFORMER "Parity"\nTITLE "Cue Sheet"\nFILE "album.flac" WAVE\n'
          '  TRACK 01 AUDIO\n    TITLE "First"\n    INDEX 01 00:00:00\n'
          '  TRACK 02 AUDIO\n    TITLE "Second"\n    INDEX 01 00:03:00\n'
          '  TRACK 03 AUDIO\n    TITLE "Third"\n    INDEX 01 00:06:00\n')
    write(os.path.join(OUT, "playlist.m3u"),
          "#EXTM3U\n#EXTINF:3,Parity - Opus\ntone.opus\n#EXTINF:3,Parity - Vorbis\ntone.ogg\n"
          "#EXTINF:3,Parity - ALAC\ntone-alac.m4a\n")
    write(os.path.join(OUT, "playlist.pls"),
          "[playlist]\nFile1=tone.opus\nTitle1=Opus\nLength1=3\nFile2=tone.wma\nTitle2=WMA\nLength2=3\n"
          "NumberOfEntries=2\nVersion=2\n")
    write(os.path.join(OUT, "playlist.xspf"),
          '<?xml version="1.0" encoding="UTF-8"?>\n<playlist version="1" xmlns="http://xspf.org/ns/0/">\n'
          '  <trackList>\n'
          '    <track><location>tone.ogg</location><title>Vorbis</title></track>\n'
          '    <track><location>tone.mka</location><title>E-AC-3</title></track>\n'
          '    <track><location>tone.aiff</location><title>AIFF</title></track>\n'
          '  </trackList>\n</playlist>\n')


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"generatedBy": "Tools/make_parity_samples.py", "samples": []}
    for entry in SAMPLES:
        path = os.path.join(OUT, entry["file"])
        ffmpeg(*entry["inputs"], *entry["args"], path)
        info = probe(path)
        manifest["samples"].append(dict(file=entry["file"], engine=entry["engine"], covers=entry["covers"], **info))
        print(f"{entry['file']}: {os.path.getsize(path) // 1024} KB")
    # Sidecar subtitles next to sidecar.mkv, as the library finds them.
    shutil.copy(SUBS["subs.srt"], os.path.join(OUT, "sidecar.srt"))
    shutil.copy(SUBS["subs.vtt"], os.path.join(OUT, "sidecar.fr.vtt"))
    for entry in manifest["samples"]:
        if entry["file"] == "sidecar.mkv":
            entry["externalSubtitles"] = ["sidecar.srt", "sidecar.fr.vtt"]

    make_dvd()
    for name, covers in (("dvdsub.mkv", ["Subtitles: DVD (VobSub) pictures"]),):
        info = probe(os.path.join(OUT, name))
        manifest["samples"].append(dict(file=name, engine="vlc", covers=covers, **info))
    manifest["discs"] = [
        dict(path="dvd", kind="videoTS", titles=2, hasMenu=True, covers=["Discs: VIDEO_TS folder with a menu"]),
        dict(path="dvd.iso", kind="iso", titles=2, hasMenu=True, covers=["Discs: DVD ISO image"]),
    ]
    make_playlists()
    manifest["playlists"] = [
        dict(file="playlist.m3u", items=["tone.opus", "tone.ogg", "tone-alac.m4a"], covers=["Playlists: M3U"]),
        dict(file="playlist.pls", items=["tone.opus", "tone.wma"], covers=["Playlists: PLS"]),
        dict(file="playlist.xspf", items=["tone.ogg", "tone.mka", "tone.aiff"], covers=["Playlists: XSPF"]),
        dict(file="album.cue", items=["album.flac", "album.flac", "album.flac"], starts=[0, 3, 6],
             covers=["Playlists: CUE sheet"]),
    ]
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    total = sum(os.path.getsize(os.path.join(root, name)) for root, _, names in os.walk(OUT) for name in names)
    print(f"total: {total // 1024} KB in {OUT}")


main()
