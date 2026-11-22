"""Shared ZIP format and checksums for the Windows release artifacts."""
import hashlib
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]


def version(package):
    text = (package / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[\w.-]+)?)(?:\+[\w.-]+)?\s*$", text, re.M)
    if not match:
        raise ValueError(f"Missing release version in {package}/pubspec.yaml")
    return match[1]


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as data:
        while chunk := data.read(1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def archive(path, files):
    # Opening members by name keeps filesystem timestamps and local paths out.
    with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, source in sorted(files.items()):
            with source.open("rb") as data, output.open(name, "w") as entry:
                shutil.copyfileobj(data, entry, 1024 * 1024)
    with zipfile.ZipFile(path) as check:
        bad = check.testzip()
        if bad:
            raise ValueError(f"CRC verification failed for {bad}")


def write_checksums(directory):
    names = [
        f"NamiHub-Interop-{version(PROJECT)}-windows-x64.zip",
        f"nami_hub_client-{version(PROJECT / 'packages/nami_hub_client')}.zip",
    ]
    if (PROJECT / "desktop/pubspec.yaml").is_file():
        names.insert(0, f"NamiHub-Desktop-{version(PROJECT / 'desktop')}-windows-x64.zip")
    with tempfile.TemporaryDirectory(dir=directory) as staging:
        checksums = []
        for name in names:
            path = directory / name
            if path.is_file():
                line = f"{digest(path)}  {name}\n"
                checksum = Path(staging) / (name + ".sha256")
                checksum.write_text(line, encoding="ascii")
                checksum.replace(directory / checksum.name)
                checksums.append(line)
        sums = Path(staging) / "SHA256SUMS.txt"
        sums.write_text("".join(checksums), encoding="ascii")
        sums.replace(directory / sums.name)
