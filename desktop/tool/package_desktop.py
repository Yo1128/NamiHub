"""Package the Flutter Release runtime and its application-local Visual C++ libraries."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
from release_archives import PROJECT, archive, digest, version, write_checksums


def vc_runtime(binary_files, cmake_cache):
    match = re.search(r"^CMAKE_GENERATOR_INSTANCE:INTERNAL=(.+)$", cmake_cache.read_text("utf-8"), re.M)
    if not match:
        raise ValueError(f"Visual Studio installation missing from {cmake_cache}")
    vc = Path(match[1].strip()) / "VC"
    aux = vc / "Auxiliary/Build"
    redist_version = (aux / "Microsoft.VCRedistVersion.default.txt").read_text().strip()
    tools_version = (aux / "Microsoft.VCToolsVersion.default.txt").read_text().strip()
    crt, = (vc / "Redist/MSVC" / redist_version / "x64").glob("Microsoft.VC*.CRT")
    redist = {dll.name.lower(): dll for dll in crt.glob("*.dll")}
    dumpbin = vc / "Tools/MSVC" / tools_version / "bin/Hostx64/x64/dumpbin.exe"
    # Follow direct and delay imports of the app, engine, and each resolved CRT.
    bundled = {f.name.lower() for f in binary_files}
    queue = list(binary_files)
    extra = {}
    system = Path(os.environ["SystemRoot"]) / "System32"
    while queue:
        binary = queue.pop()
        imports = subprocess.check_output([str(dumpbin), "/nologo", "/dependents", str(binary)])
        dependencies = re.findall(rb"^\s*([\w.-]+\.dll)\s*$", imports, re.I | re.M)
        for raw in dependencies:
            name = raw.decode("ascii").lower()
            if name in bundled or name in extra:
                continue
            if name in redist:
                extra[name] = redist[name]
                queue.append(redist[name])
            elif name.startswith(("api-ms-win-", "ext-ms-win-")):
                continue
            elif name.startswith(("msvcp", "vcruntime", "concrt", "vccorlib")) or not (system / name).is_file():
                raise ValueError(f"{binary.name} has an unresolved dependency: {name}")
    return extra


def collect(runtime, cache):
    files = {name: runtime / name for name in (
        "NamiHub.exe", "flutter_windows.dll", "data/app.so", "data/icudtl.dat",
    )}
    assets = runtime / "data/flutter_assets"
    if not (assets / "NOTICES.Z").is_file():
        raise ValueError("Flutter license bundle is missing")
    for path in assets.rglob("*"):
        if path.is_file():
            files[path.relative_to(runtime).as_posix()] = path
    hub_files = {"init_tls.ps1": PROJECT / "tool/init_tls.ps1"}
    for source in (PROJECT / "fixtures/media").iterdir():
        if source.name == "harbor-seek.mp4":
            source = PROJECT / "desktop/assets" / source.name
        hub_files["media/" + source.name] = source
    for name, source in hub_files.items():
        path = runtime / "data/hub" / name
        if digest(source) != digest(path):
            raise ValueError(f"Installed data/hub/{name} differs from the source. Rebuild the Release runtime.")
        files["data/hub/" + name] = path
    files.update(vc_runtime([files["NamiHub.exe"], files["flutter_windows.dll"]], cache))
    files["notices/Visual-C++-Runtime.txt"] = PROJECT / "desktop/tool/Visual-C++-Runtime.txt"
    if (PROJECT / "LICENSE").is_file():
        files["LICENSE"] = PROJECT / "LICENSE"
    return files


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runtime, output = args.runtime.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    files = collect(runtime, runtime.parents[1] / "CMakeCache.txt")
    name = f"NamiHub-Desktop-{version(PROJECT / 'desktop')}-windows-x64.zip"
    with tempfile.TemporaryDirectory(dir=output) as temp:
        packed = Path(temp) / name
        archive(packed, files)
        packed.replace(output / name)
    write_checksums(output)
    print(output / name)
