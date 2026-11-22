"""Regenerate the synthetic, redistributable interoperability files (Python 3 and FFmpeg)."""
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1] / "fixtures"
MEDIA = ROOT / "media"
MEDIA.mkdir(parents=True, exist_ok=True)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *map(str, args)], check=True)


def epub():
    entries = {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        "book.opf": '''<package version="3.0" unique-identifier="uid" xmlns="http://www.idpf.org/2007/opf">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>潮汐手记</dc:title><dc:identifier id="uid">urn:uuid:7c5cb35e-4c91-44f4-a208-4c1c836f64d9</dc:identifier><dc:language>zh</dc:language><meta property="dcterms:modified">2026-11-20T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
        "nav.xhtml": '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="a.xhtml">抵港</a></li><li><a href="b.xhtml">涨潮</a></li></ol></nav></body></html>',
    }
    for name, title, paragraph in [("a", "抵港", "午后的渡船靠岸了。"), ("b", "涨潮", "水线一点点爬过石阶。")]:
        entries[name + ".xhtml"] = f'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head><body><h1>{title}</h1>' + "".join(f"<p>{i}　{paragraph}</p>" for i in range(1, 81)) + "</body></html>"
    with zipfile.ZipFile(MEDIA / "tide-notes.epub", "w") as archive:
        for name, content in entries.items():
            entry = zipfile.ZipInfo(name, date_time=(2026, 11, 20, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            archive.writestr(entry, content.encode("utf-8"))


def main():
    text = "第一章 灯塔\n" + "".join(f"{i}　海面上的光慢慢向东移动。\n" for i in range(1, 401))
    text += "\n第二章 归航\n" + "".join(f"{i}　船靠上码头时，钟声刚好响起。\n" for i in range(1, 401))
    (MEDIA / "灯塔手记.txt").write_bytes(text.encode())
    epub()
    wav = MEDIA / "harbor-tone.wav"
    with wave.open(str(wav), "wb") as f:
        rate = 24000
        f.setparams((1, 2, rate, 0, "NONE", ""))
        f.writeframes(b"".join(struct.pack("<h", round(4500 * math.sin(2 * math.pi * (330 if i < rate * 4 else 440) * i / rate))) for i in range(rate * 8)))
    ffmpeg("-i", wav, "-codec:a", "libmp3lame", "-q:a", 4, "-metadata", "title=Harbor Tone", MEDIA / "harbor-tone.mp3")
    ffmpeg("-f", "lavfi", "-i", "testsrc2=size=480x270:rate=24", "-f", "lavfi", "-i", "sine=frequency=330:sample_rate=44100", "-t", 30, "-c:v", "libx264", "-threads", 1, "-preset", "veryfast", "-g", 24, "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", MEDIA / "harbor-seek.mp4")
    formats = {".txt": ("book","text/plain"), ".epub": ("book","application/epub+zip"), ".wav": ("audio","audio/wav"), ".mp3": ("audio","audio/mpeg"), ".mp4": ("video","video/mp4")}
    rows = []
    for index, path in enumerate(sorted(MEDIA.iterdir())):
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        kind, mime = formats[path.suffix]
        rows.append(dict(resourceId=f"fixture_{index+1}", displayName=path.name, type=kind, mimeType=mime, sizeBytes=len(data), contentVersion=digest, sha256=digest))
    write_json(ROOT / "catalog.json", {"items": rows, "nextCursor": None})
    write_json(ROOT / "pages" / "first.json", {"items": rows[:2], "nextCursor": rows[1]["resourceId"]})
    write_json(ROOT / "pages" / "second.json", {"items": rows[2:4], "nextCursor": rows[3]["resourceId"]})
    write_json(ROOT / "pages" / "last.json", {"items": rows[4:], "nextCursor": None})
    write_json(ROOT / "errors.json", [{"status": status, "body": {"error": code}} for status, code in [
        (401,"unauthorized"), (403,"invalid_pair_code"), (403,"pairing_closed"), (404,"resource_missing"),
        (409,"rescan_required"), (412,"version_changed"), (416,"range_not_satisfiable")]])


if __name__ == "__main__":
    main()
