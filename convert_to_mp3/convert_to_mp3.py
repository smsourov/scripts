#!/usr/bin/env python3
"""
convert_to_mp3.py
=================
Batch-converts MKV/MP4 files to MP3 with full metadata mapping.

Metadata mapping:
  mp3 Title        ← mkv movie name (title tag)
  mp3 Artist       ← mkv artist tag
  mp3 Album        ← mkv artist tag  (same as artist, by design)
  mp3 Year         ← mkv date / recorded_date  (YYYYMMDD → YYYY)
  mp3 Comment      ← mkv comment tag
  mp3 Cover Image  ← mkv attached picture stream
  mp3 Lyrics       ← first SRT subtitle stream → converted to LRC format

Requirements:
  pip install mutagen

Usage:
  python convert_to_mp3.py <input_dir> <output_dir>

Examples:
  python convert_to_mp3.py "D:/Videos" "D:/Music"
  python convert_to_mp3.py ./videos ./mp3s
"""

import subprocess
import json
import os
import re
import sys
import tempfile
import argparse
from pathlib import Path

# ── Dependency check ────────────────────────────────────────────────────────
try:
    from mutagen.id3 import (
        ID3, ID3NoHeaderError,
        TIT2,   # Title
        TPE1,   # Artist
        TALB,   # Album
        TDRC,   # Recording year
        COMM,   # Comment
        USLT,   # Unsynchronised lyrics
        APIC,   # Attached picture (cover art)
    )
except ImportError:
    print("❌  mutagen is not installed.")
    print("    Run:  pip install mutagen")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════════

def run_cmd(cmd: list) -> subprocess.CompletedProcess:
    """Run a subprocess command silently and return the result."""
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def get_ffprobe_data(filepath: Path) -> dict:
    """Return parsed ffprobe JSON for the given file."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        str(filepath)
    ]
    result = run_cmd(cmd)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed:\n{result.stderr}")
    return json.loads(result.stdout)


def get_tag(tags: dict, *keys: str) -> str | None:
    """
    Look up a tag case-insensitively, trying each key in order.
    Returns the first non-empty match, or None.
    """
    tags_ci = {k.lower(): v for k, v in tags.items()}
    for key in keys:
        val = tags_ci.get(key.lower())
        if val and val.strip():
            return val.strip()
    return None


def extract_year(date_str: str | None) -> str | None:
    """
    Extract a 4-digit year from strings like:
      20031231   YYYYMMDD
      2003-12-31 YYYY-MM-DD
      2003       YYYY
      2003/12/31 YYYY/MM/DD
    Returns the year string, or None.
    """
    if not date_str:
        return None
    match = re.search(r'(\d{4})', date_str)
    return match.group(1) if match else None


# ═══════════════════════════════════════════════════════════════════════════
#  Stream discovery
# ═══════════════════════════════════════════════════════════════════════════

def find_cover_stream(streams: list) -> int | None:
    """
    Return the stream index of an attached picture, or None.
    An attached picture is a video stream with disposition.attached_pic = 1.
    """
    for stream in streams:
        if stream.get("codec_type") == "video":
            disp = stream.get("disposition", {})
            if disp.get("attached_pic", 0) == 1:
                return stream["index"]
    return None


def find_srt_subtitle_streams(streams: list) -> list[int]:
    """
    Return a list of stream indices that are SRT/SubRip subtitle tracks,
    in stream order.  Only subrip-compatible codecs are included.
    """
    srt_codecs = {"subrip", "srt", "text", "ass", "ssa", "webvtt"}
    result = []
    for stream in streams:
        if stream.get("codec_type") == "subtitle":
            codec = stream.get("codec_name", "").lower()
            if codec in srt_codecs:
                result.append(stream["index"])
    return result


# ═══════════════════════════════════════════════════════════════════════════
#  SRT → LRC conversion
# ═══════════════════════════════════════════════════════════════════════════

def srt_timestamp_to_ms(h: int, m: int, s: int, ms: int) -> int:
    """Convert hours/minutes/seconds/milliseconds to a total millisecond integer."""
    return ((h * 60 + m) * 60 + s) * 1000 + ms


def ms_to_lrc_timestamp(total_ms: int) -> str:
    """
    Convert a millisecond value to LRC timestamp format [MM:SS.mmm].
    Uses 3-digit milliseconds for full precision.
    """
    total_seconds, ms  = divmod(total_ms, 1000)
    total_minutes, sec = divmod(total_seconds, 60)
    return f"[{total_minutes:02d}:{sec:02d}.{ms:03d}]"


def parse_srt_timestamp(ts_str: str) -> int | None:
    """
    Parse a single SRT timestamp string (HH:MM:SS,mmm or HH:MM:SS.mmm)
    and return total milliseconds, or None if unparseable.
    """
    m = re.match(r'(\d+):(\d{2}):(\d{2})[,.](\d{3})', ts_str.strip())
    if not m:
        return None
    return srt_timestamp_to_ms(int(m.group(1)), int(m.group(2)),
                                int(m.group(3)), int(m.group(4)))


def clean_subtitle_text(raw: str) -> str:
    """Strip HTML tags and ASS override blocks from a subtitle text line."""
    cleaned = re.sub(r'<[^>]+>', '', raw)
    cleaned = re.sub(r'\{[^}]+\}', '', cleaned)
    return cleaned.strip()


def srt_to_lrc(srt_content: str) -> str:
    """
    Convert SRT subtitle content to LRC format.

    For each cue the START timestamp + text is emitted.
    When there is a gap between a cue's END time and the next cue's START time,
    a blank timed line is inserted at the END timestamp to mark the silence:

        SRT:
            1  00:00:02,640 --> 00:00:04,260   "I'm sorry but"
            2  00:00:05,300 --> 00:00:06,860   "Don't wanna talk"
            3  00:00:06,860 --> 00:00:09,920   "I need a moment before i go"

        LRC:
            [00:02.640]I'm sorry but
            [00:04.260]                  ← gap: cue 1 ends at 4260, cue 2 starts at 5300
            [00:05.300]Don't wanna talk
            [00:06.860]I need a moment before i go
                                          ← no gap: cue 2 ends at 6860 = cue 3 starts at 6860
            [00:09.920]                  ← gap: cue 3 ends at 9920, cue 4 starts at 10920
            ...
    """
    # ── 1. Parse every cue block ──────────────────────────────────────────
    cues = []   # list of (start_ms, end_ms, [text_lines])

    blocks = re.split(r'\n\s*\n', srt_content.strip())
    for block in blocks:
        lines = block.strip().splitlines()
        if not lines:
            continue

        # Locate the "start --> end" line
        ts_line_idx = None
        for idx, line in enumerate(lines):
            if "-->" in line:
                ts_line_idx = idx
                break
        if ts_line_idx is None:
            continue

        ts_parts = lines[ts_line_idx].split("-->")
        start_ms = parse_srt_timestamp(ts_parts[0])
        end_ms   = parse_srt_timestamp(ts_parts[1]) if len(ts_parts) > 1 else None
        if start_ms is None or end_ms is None:
            continue

        text_lines = [
            clean_subtitle_text(l)
            for l in lines[ts_line_idx + 1:]
            if clean_subtitle_text(l)
        ]
        if text_lines:
            cues.append((start_ms, end_ms, text_lines))

    if not cues:
        return ""

    # ── 2. Build LRC lines ────────────────────────────────────────────────
    lrc_lines = []

    for i, (start_ms, end_ms, text_lines) in enumerate(cues):
        # Emit all text lines at the start timestamp
        start_ts = ms_to_lrc_timestamp(start_ms)
        for text in text_lines:
            lrc_lines.append(f"{start_ts}{text}")

        # Check for a gap before the next cue
        if i < len(cues) - 1:
            next_start_ms = cues[i + 1][0]
            if end_ms < next_start_ms:
                # Insert a blank timed line at this cue's end timestamp
                lrc_lines.append(ms_to_lrc_timestamp(end_ms))

    return "\n".join(lrc_lines)


# ═══════════════════════════════════════════════════════════════════════════
#  Core conversion logic
# ═══════════════════════════════════════════════════════════════════════════

def extract_cover(input_path: Path, stream_index: int, tmpdir: Path) -> tuple[bytes | None, str]:
    """
    Extract the cover image from the given stream index.
    Returns (raw_bytes, mime_type) or (None, '').
    """
    cover_path = tmpdir / "cover_art"
    cmd = [
        "ffmpeg", "-y", "-i", str(input_path),
        "-map", f"0:{stream_index}",
        "-frames:v", "1",
        "-f", "image2",
        str(cover_path)   # ffmpeg will add extension if it can infer it
    ]
    result = run_cmd(cmd)

    # ffmpeg might write cover_art or cover_art.jpg / .png – find it
    candidates = list(tmpdir.glob("cover_art*"))
    if result.returncode != 0 or not candidates:
        return None, ""

    cover_file = candidates[0]
    ext = cover_file.suffix.lower()
    mime = "image/jpeg" if ext in (".jpg", ".jpeg") else \
           "image/png"  if ext == ".png"            else \
           "image/jpeg"                               # safe fallback
    return cover_file.read_bytes(), mime


def extract_subtitle_as_srt(input_path: Path, stream_index: int, tmpdir: Path) -> str | None:
    """
    Extract the subtitle stream at stream_index as SRT text.
    Returns the text content, or None on failure.
    """
    srt_path = tmpdir / "subtitle.srt"
    cmd = [
        "ffmpeg", "-y", "-i", str(input_path),
        "-map", f"0:{stream_index}",
        str(srt_path)
    ]
    result = run_cmd(cmd)
    if result.returncode != 0 or not srt_path.exists():
        return None
    return srt_path.read_text(encoding="utf-8", errors="replace")


def convert_audio_to_mp3(input_path: Path, output_path: Path) -> bool:
    """
    Use ffmpeg to convert the audio track to MP3.
    Uses high-quality VBR (~190 kbps).  No video, no subtitles.
    Returns True on success.
    """
    cmd = [
        "ffmpeg", "-y",
        "-i", str(input_path),
        "-vn",                    # no video streams
        "-sn",                    # no subtitle streams
        "-acodec", "libmp3lame",
        "-q:a", "2",              # VBR quality 0 (best)–9 (worst); 2 ≈ 190 kbps
        str(output_path)
    ]
    result = run_cmd(cmd)
    return result.returncode == 0


def write_id3_tags(
    mp3_path:   Path,
    title:      str | None,
    artist:     str | None,
    year:       str | None,
    comment:    str | None,
    lyrics_lrc: str | None,
    cover_data: bytes | None,
    cover_mime: str,
) -> None:
    """
    Write ID3v2.3 tags to the MP3 using mutagen.
    Clears any existing values for the tags we manage before writing.
    """
    try:
        tags = ID3(str(mp3_path))
    except ID3NoHeaderError:
        tags = ID3()

    # Clear managed frames so we start clean
    for frame_key in ("TIT2", "TPE1", "TALB", "TDRC", "COMM", "USLT", "APIC"):
        tags.delall(frame_key)

    if title:
        tags["TIT2"] = TIT2(encoding=3, text=title)

    if artist:
        tags["TPE1"] = TPE1(encoding=3, text=artist)
        tags["TALB"] = TALB(encoding=3, text=artist)   # Album = Artist (per spec)

    if year:
        tags["TDRC"] = TDRC(encoding=3, text=year)

    if comment:
        tags["COMM"] = COMM(encoding=3, lang="eng", desc="", text=comment)

    if lyrics_lrc:
        tags["USLT"] = USLT(encoding=3, lang="eng", desc="", text=lyrics_lrc)

    if cover_data:
        tags["APIC"] = APIC(
            encoding=3,
            mime=cover_mime,
            type=3,           # 3 = Cover (front)
            desc="Cover",
            data=cover_data,
        )

    tags.save(str(mp3_path), v2_version=3)


# ═══════════════════════════════════════════════════════════════════════════
#  Per-file processor
# ═══════════════════════════════════════════════════════════════════════════

def process_file(input_path: Path, output_dir: Path) -> bool:
    output_path = output_dir / (input_path.stem + ".mp3")

    print(f"\n{'─' * 60}")
    print(f"  IN  : {input_path.name}")
    print(f"  OUT : {output_path.name}")
    print(f"{'─' * 60}")

    # ── 1. Probe ──────────────────────────────────────────────────────────
    try:
        probe = get_ffprobe_data(input_path)
    except Exception as exc:
        print(f"  [SKIP] Could not probe file: {exc}")
        return False

    fmt_tags = probe.get("format", {}).get("tags", {})
    streams  = probe.get("streams", [])

    # ── 2. Read metadata tags ─────────────────────────────────────────────
    title   = get_tag(fmt_tags, "title", "TITLE")
    artist  = get_tag(fmt_tags, "artist", "ARTIST")
    comment = get_tag(fmt_tags, "comment", "COMMENT")

    # Date: prefer 'date', fall back to 'recorded_date', then 'creation_time'
    date_raw = (
        get_tag(fmt_tags, "date", "DATE") or
        get_tag(fmt_tags, "recorded_date", "RECORDED_DATE") or
        get_tag(fmt_tags, "creation_time")
    )
    year = extract_year(date_raw)

    # Lyrics stored directly in metadata (rare but possible)
    lyrics_tag = get_tag(fmt_tags, "lyrics", "LYRICS", "UNSYNCEDLYRICS")

    print(f"  Title   : {title   or '(none)'}")
    print(f"  Artist  : {artist  or '(none)'}")
    print(f"  Year    : {year    or '(none)'}  ← raw: {date_raw or 'none'}")
    print(f"  Comment : {(comment[:60] + '…') if comment and len(comment) > 60 else (comment or '(none)')}")

    with tempfile.TemporaryDirectory() as _tmpdir:
        tmpdir = Path(_tmpdir)

        # ── 3. Cover image ────────────────────────────────────────────────
        cover_data = None
        cover_mime = "image/jpeg"
        cover_idx  = find_cover_stream(streams)

        if cover_idx is not None:
            cover_data, cover_mime = extract_cover(input_path, cover_idx, tmpdir)
            if cover_data:
                print(f"  Cover   : ✓ extracted ({len(cover_data):,} bytes, {cover_mime})")
            else:
                print(f"  Cover   : ✗ extraction failed (stream {cover_idx} found but unreadable)")
        else:
            print(f"  Cover   : — no attached picture stream found")

        # ── 4. Lyrics / subtitles ─────────────────────────────────────────
        lyrics_lrc = None

        if lyrics_tag:
            # Metadata already has lyrics — use them as-is
            lyrics_lrc = lyrics_tag
            print(f"  Lyrics  : ✓ from metadata tag ({len(lyrics_lrc)} chars)")
        else:
            srt_stream_indices = find_srt_subtitle_streams(streams)
            if srt_stream_indices:
                first_srt_idx = srt_stream_indices[0]
                srt_content = extract_subtitle_as_srt(input_path, first_srt_idx, tmpdir)
                if srt_content:
                    lyrics_lrc = srt_to_lrc(srt_content)
                    skipped = len(srt_stream_indices) - 1
                    print(
                        f"  Lyrics  : ✓ SRT stream {first_srt_idx} → LRC "
                        f"({len(lyrics_lrc)} chars)"
                        + (f"  [{skipped} other subtitle stream(s) skipped]" if skipped else "")
                    )
                else:
                    print(f"  Lyrics  : ✗ SRT extraction failed (stream {first_srt_idx})")
            else:
                print(f"  Lyrics  : — no SRT subtitle streams found")

        # ── 5. Convert audio ──────────────────────────────────────────────
        print(f"  Converting audio …")
        if not convert_audio_to_mp3(input_path, output_path):
            print(f"  [ERROR] ffmpeg conversion failed — skipping")
            return False

        # ── 6. Write ID3 tags ─────────────────────────────────────────────
        try:
            write_id3_tags(
                mp3_path   = output_path,
                title      = title,
                artist     = artist,
                year       = year,
                comment    = comment,
                lyrics_lrc = lyrics_lrc,
                cover_data = cover_data,
                cover_mime = cover_mime,
            )
        except Exception as exc:
            print(f"  [ERROR] Failed to write ID3 tags: {exc}")
            return False

    print(f"  [DONE] ✓")
    return True


# ═══════════════════════════════════════════════════════════════════════════
#  Entry point
# ═══════════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Batch-convert MKV/MP4 → MP3 with full metadata mapping.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("input_dir",  help="Directory containing .mkv / .mp4 files")
    parser.add_argument("output_dir", help="Directory where .mp3 files will be written")
    args = parser.parse_args()

    input_dir  = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    if not input_dir.is_dir():
        print(f"Error: input directory not found: {input_dir}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Collect MKV and MP4 files (case-insensitive glob via explicit patterns)
    extensions = ("*.mkv", "*.MKV", "*.mp4", "*.MP4")
    files = sorted({f for ext in extensions for f in input_dir.glob(ext)})

    if not files:
        print(f"No MKV/MP4 files found in: {input_dir}")
        sys.exit(0)

    print(f"Found {len(files)} file(s) in '{input_dir}'")
    print(f"Output directory: '{output_dir}'")

    success_count = 0
    for f in files:
        if process_file(f, output_dir):
            success_count += 1

    print(f"\n{'═' * 60}")
    print(f"  Completed: {success_count} / {len(files)} file(s) converted successfully.")
    print(f"{'═' * 60}\n")

    if success_count < len(files):
        sys.exit(1)


if __name__ == "__main__":
    main()
