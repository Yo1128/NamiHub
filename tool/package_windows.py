"""Build Windows and SDK handoff archives, verify the binary, and record checksums."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import zipfile

from release_archives import PROJECT, archive, digest, version, write_checksums
from verify import RunningHub, verify

DIST = PROJECT / "dist"
BUILD = PROJECT / "build"


def sources(folder):
    return [f for f in folder.rglob("*") if f.is_file() and
            not {".dart_tool","__pycache__","build"}.intersection(f.relative_to(folder).parts)]


def check_archives(kit, sdk_zip, dart):
    with tempfile.TemporaryDirectory(prefix="NamiHub 联调 ") as work:
        work = Path(work)
        unpacked = work/"Windows kit"
        client = work/"independent SDK"
        for path,target in [(kit,unpacked),(sdk_zip,client)]:
            with zipfile.ZipFile(path) as archive_file:
                archive_file.extractall(target)
        subprocess.run([dart,"pub","get","--offline"],cwd=client,check=True,capture_output=True)
        subprocess.run([dart,"analyze"],cwd=client,check=True,capture_output=True)
        state = work/"state"
        launch = ["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(unpacked/"Start-NamiHub.ps1"),"-StateDirectory",str(state),"-Port","0","-Lan","-TraceReads","-OperatorPipe"]
        hub = RunningHub(None,unpacked/"fixtures/media",state,launch)
        try:
            demo = subprocess.run([dart,"run","example/connect.dart",hub.origin,hub.ready["certificateSha256"]],cwd=client,input=hub.code+"\n",capture_output=True,encoding="utf-8",errors="replace",timeout=25)
            if demo.returncode or "harbor-seek.mp4" not in demo.stdout:
                raise RuntimeError("Separate SDK example failed: "+demo.stderr)
            require_code = hub.command("pair","pairCode")["code"]
            lan = subprocess.run([dart,"run","example/pair_lan.dart"],cwd=client,input=require_code+"\n",capture_output=True,encoding="utf-8",errors="replace",timeout=30)
            if lan.returncode or "tide-notes.epub" not in lan.stdout:
                raise RuntimeError("Packaged LAN pairing failed: "+lan.stderr)
            code = hub.command("pair","pairCode")["code"]
            token = hub.pair(code,201)["accessToken"]
            audio = json.loads(hub.request("GET","/v1/resources?type=audio",200,token)[1])["items"][0]
            _, data = hub.request("GET","/v1/resources/"+audio["resourceId"]+"/content",200,token)
            if hashlib.sha256(data).hexdigest()!=audio["sha256"]:
                raise RuntimeError("Unpacked service returned incorrect audio")
        finally:
            hub.stop()


def notices(dart):
    config = PROJECT / ".dart_tool/package_config.json"
    resolved = json.loads(config.read_text("utf-8"))
    files = {}
    for pkg in resolved["packages"]:
        if pkg["name"] in {"nami_hub", "nami_hub_client"}:
            continue
        uri = urllib.parse.urljoin(config.as_uri(), pkg["rootUri"])
        folder = Path(urllib.request.url2pathname(urllib.parse.urlsplit(uri).path))
        files[f"notices/{pkg['name']}-LICENSE.txt"] = folder / "LICENSE"
    sdk = resolved.get("flutterRoot")
    if sdk:
        flutter = Path(urllib.request.url2pathname(urllib.parse.urlsplit(sdk).path))
        dart_license = flutter / "bin/cache/dart-sdk/LICENSE"
    else:
        dart_license = Path(dart).resolve().parents[1] / "LICENSE"
    files["notices/dart-sdk-LICENSE.txt"] = dart_license
    return files


def main(output):
    output.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(exist_ok=True)
    dart = shutil.which("dart")
    if not dart:
        raise RuntimeError("Dart SDK is required to build the handoff archives")
    exe = BUILD / "nami_hub.exe"
    subprocess.run([dart,"compile","exe","bin/nami_hub.dart","-o",str(exe)],cwd=PROJECT,check=True)
    with tempfile.TemporaryDirectory(prefix="namihub-package-test-") as work:
        results = verify(exe, Path(work))
    service_version = version(PROJECT)
    sdk = PROJECT / "packages/nami_hub_client"
    results.update(version=service_version, platform=platform.platform(), executableSha256=digest(exe))
    with tempfile.TemporaryDirectory(dir=output) as work:
        stage = Path(work)
        report = stage / f"verification-windows-{service_version}.json"
        report.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        sdk_files = {f.relative_to(sdk).as_posix(): f for f in sources(sdk) if f.name != "pubspec.lock"}
        if (PROJECT / "LICENSE").is_file():
            sdk_files.setdefault("LICENSE", PROJECT / "LICENSE")
        sdk_zip = stage / f"nami_hub_client-{version(sdk)}.zip"
        archive(sdk_zip, sdk_files)
        files = {"nami_hub.exe": exe, **notices(dart)}
        for folder in ["bin", "lib", "tool", "fixtures", "packages"]:
            files.update({f.relative_to(PROJECT).as_posix(): f for f in sources(PROJECT / folder)})
        for f in (PROJECT / "docs").glob("*"):
            if f.suffix in {".md", ".json"} and f.is_file():
                files[f"docs/{f.name}"] = f
        files["docs/" + report.name] = report
        for name in ["README.md", "pubspec.yaml", "pubspec.lock", "Start-NamiHub.ps1"]:
            files[name] = PROJECT / name
        if (PROJECT / "LICENSE").is_file():
            files["LICENSE"] = PROJECT / "LICENSE"
        kit = stage / f"NamiHub-Interop-{service_version}-windows-x64.zip"
        archive(kit, files)
        check_archives(kit, sdk_zip, dart)
        for path in (kit, sdk_zip):
            path.replace(output / path.name)
            print(output / path.name)
        shutil.copyfile(report, PROJECT / "docs" / report.name)
        write_checksums(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DIST)
    main(parser.parse_args().output.resolve())
