"""Stage pinned PDFium libraries and all licenses without editing platform trees."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import tarfile
import urllib.request


def host_target():
    host = (platform.system(), platform.machine().lower())
    return {
        ("Darwin", "arm64"): "aarch64-apple-darwin",
        ("Windows", "amd64"): "x86_64-pc-windows-msvc",
        ("Windows", "x86_64"): "x86_64-pc-windows-msvc",
        ("Linux", "x86_64"): "x86_64-unknown-linux-gnu",
    }.get(host)


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / "rust/pdfium-binaries.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default="host")
    parser.add_argument("--output", type=Path, default=root / "rust/native")
    args = parser.parse_args()
    target = host_target() if args.target == "host" else args.target
    if target not in manifest["targets"]:
        parser.error("unsupported PDFium target")
    entry = manifest["targets"][target]
    output = args.output.resolve() / target
    output.mkdir(parents=True, exist_ok=True)
    archive = output / entry["archive"]
    if not archive.exists():
        url = ("https://github.com/bblanchon/pdfium-binaries/releases/download/"
               f"{manifest['release']}/{entry['archive']}")
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as file:
            while chunk := response.read(1024 * 1024):
                file.write(chunk)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != entry["sha256"]:
        raise SystemExit("PDFium archive checksum mismatch; no library was loaded")
    with tarfile.open(archive) as package:
        package.extractall(output, filter="data")
    if not (output / "LICENSE").is_file() or not (output / "licenses").is_dir():
        raise SystemExit("PDFium license bundle is missing")
    libraries = list(output.rglob(entry["library"]))
    if len(libraries) != 1:
        raise SystemExit("PDFium archive has an unexpected library layout")
    print(libraries[0])


if __name__ == "__main__":
    main()
