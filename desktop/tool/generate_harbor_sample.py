"""Rebuild the desktop preview with Python, Pillow and FFmpeg. No external media."""
from math import pi, sin
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw


def render():
    width, height, fps, duration = 480, 270, 15, 30
    output = Path(__file__).resolve().parents[1] / "assets" / "harbor-seek.mp4"
    output.parent.mkdir(exist_ok=True)
    base = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(base)
    horizon = 169
    for y in range(height):
        start, end, t = ((34, 46, 75), (224, 162, 148), y / horizon) if y < horizon else (
            (79, 110, 128), (31, 56, 78), (y - horizon) / (height - horizon))
        draw.line((0, y, width, y), fill=tuple(round(a + (b - a) * t) for a, b in zip(start, end)))
    draw.ellipse((315, 95, 346, 126), fill=(248, 209, 171))
    draw.polygon([(0, 167), (64, 144), (94, 147), (159, 124), (234, 156),
                  (303, 133), (391, 152), (464, 140), (480, 146), (480, 169), (0, 169)],
                 fill=(114, 108, 128))
    draw.polygon([(0, 145), (57, 152), (91, 163), (130, 164), (166, 171),
                  (98, 174), (0, 168)], fill=(50, 66, 83))
    draw.polygon([(80, 158), (82, 128), (88, 128), (90, 160)], fill=(223, 203, 179))
    draw.rectangle((81, 127, 89, 131), fill=(249, 210, 140))
    draw.polygon([(79, 127), (85, 122), (91, 127)], fill=(52, 61, 74))
    # A quiet, decaying two-note signal repeats while the boat crosses the inlet.
    tone = "aevalsrc=0.06*exp(-2*mod(t\\,6))*(sin(2*PI*330*t)+0.35*sin(2*PI*495*t)):s=24000"
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pixel_format", "rgb24",
           "-video_size", f"{width}x{height}", "-framerate", str(fps), "-i", "pipe:0",
           "-f", "lavfi", "-i", tone, "-t", str(duration), "-c:v", "libx264", "-threads", "1",
           "-preset", "slow", "-crf", "27", "-g", str(fps * 2), "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "32k", "-movflags", "+faststart", str(output)]
    with subprocess.Popen(cmd, stdin=subprocess.PIPE) as encoder:
        for n in range(fps * duration):
            frame = base.copy()
            ink = ImageDraw.Draw(frame)
            t = n / fps
            for i in range(33):
                x = (i * 79 + round(5 * sin(i + t * .6))) % width
                y = 172 + i * 31 % 98
                ink.line((x, y, x + 4 + y % 14, y), fill=(95, 121, 132))
            x = round(170 + t * 6)
            y = 184 + round(sin(t * pi / 3))
            ink.polygon([(x, y), (x + 26, y), (x + 21, y + 4), (x + 5, y + 4)], fill=(37, 53, 65))
            ink.polygon([(x + 4, y - 2), (x + 16, y - 21), (x + 16, y - 2)], fill=(233, 208, 173))
            encoder.stdin.write(frame.tobytes())
        encoder.stdin.close()
        if encoder.wait() != 0:
            raise RuntimeError("Could not encode the desktop sample")


if __name__ == "__main__":
    render()
