#!/usr/bin/env python3
"""Generate the Rust bridge and validate Dart bindings in an isolated project.

The Flutter application and platform trees are deliberately outside this command's
outputs. Set FRB_CODEGEN, CARGO, DART and PUB_CACHE to use local tool installations.
"""
import argparse
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# FRB embeds the Dart package name in exported Rust symbols, so the isolated
# project must share the application's name to reproduce frb_generated.rs.
PUBSPEC = """name: otter_pad
environment:
  sdk: '>=3.8.0 <4.0.0'
dependencies:
  flutter_rust_bridge: 2.13.0
  freezed_annotation: 3.1.0
dev_dependencies:
  freezed: 3.2.5
  build_runner: 2.15.0
"""


def run(command, cwd, log):
    try:
        with log.open("w") as output:
            result = subprocess.run(command, cwd=cwd, stdout=output,
                                    stderr=subprocess.STDOUT, text=True,
                                    timeout=180 if log.name == "ffi.log" else 600)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"Command timed out; full log: {log}") from None
    if result.returncode:
        raise SystemExit(f"Command failed ({result.returncode}); full log: {log}\n"
                         + log.read_text()[-5000:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart-project", type=Path,
                        help="Dedicated generated project; defaults to a new temporary directory")
    parser.add_argument("--verify", action="store_true",
                        help="Resolve dependencies, generate unions and run the real Dart analyzer")
    parser.add_argument("--check-rust", action="store_true",
                        help="Fail if checked-in Rust bindings differ from regenerated output")
    parser.add_argument("--smoke", action="store_true",
                        help="Build and call the real native library from Dart (includes --verify)")
    parser.add_argument("--pdfium-library", type=Path,
                        help="PDFium library for --smoke; defaults to PDFIUM_LIBRARY_PATH")
    args = parser.parse_args()
    project = (args.dart_project or Path(tempfile.mkdtemp(prefix="otterpad-bridge-"))).resolve()
    # A typo must not turn a codegen check into an edit of the application.
    if project == ROOT or ROOT in project.parents:
        raise SystemExit("The isolated Dart project must be outside the repository")
    marker = project / ".otterpad-bridge-check"
    project.mkdir(parents=True, exist_ok=True)
    if any(project.iterdir()) and not marker.is_file():
        raise SystemExit(f"Refusing to replace an existing unowned directory: {project}")
    marker.touch()
    output = project / "lib"
    if output.exists():
        shutil.rmtree(output)
    output.mkdir()
    (project / "pubspec.yaml").write_text(PUBSPEC)
    generated = ROOT / "rust/src/frb_generated.rs"
    previous = generated.read_bytes() if generated.exists() else None
    codegen = os.environ.get("FRB_CODEGEN", "flutter_rust_bridge_codegen")
    # Leave --rust-output to FRB's default (rust/src/frb_generated.rs): FRB
    # canonicalizes the crate root, which on Windows gains a \\?\ prefix that a
    # plain absolute output path does not share.
    run([codegen, "generate", "--rust-root", str(ROOT / "rust"),
         "--rust-input", "crate::api",
         "--dart-root", str(project), "--dart-output", str(output),
         "--no-web", "--no-build-runner", "--no-deps-check",
         "--no-auto-upgrade-dependency", "--no-dart-fix", "--no-dart-format",
         "--no-rust-format",
         "--stop-on-error"], ROOT, project / "codegen.log")
    # FRB defaults to the 2021 import ordering. Match this crate's Rust 2024 style
    # so cargo fmt and codegen do not alternately rewrite the generated file.
    run([os.environ.get("RUSTFMT", "rustfmt"), "--edition", "2024", str(generated)],
        ROOT / "rust", project / "rustfmt.log")
    if args.check_rust and previous != generated.read_bytes():
        raise SystemExit("Rust bindings changed; regenerate and include them with the API change")
    if "AutoAccessor" in generated.read_text():
        raise SystemExit("Unexpected opaque field accessors in the public bridge; keep runtime state private")
    opaque = set(re.findall(r"RustAutoOpaqueInner<([^>]+)>", generated.read_text()))
    if opaque - {"Backend", "LocalZoteroSnapshot"}:
        raise SystemExit(f"Unexpected opaque business DTOs in the public bridge: {opaque}")
    if args.verify or args.smoke:
        dart = os.environ.get("DART", "dart")
        binary = project / "bin"
        binary.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / "scripts/verify_rust_bridge.dart.in", binary / "verify_bridge.dart")
        run([dart, "pub", "get"], project, project / "pub.log")
        run([dart, "run", "build_runner", "build"], project, project / "unions.log")
        run([dart, "analyze"], project, project / "analyze.log")
        if args.smoke:
            pdfium = args.pdfium_library or os.environ.get("PDFIUM_LIBRARY_PATH")
            if not pdfium or not Path(pdfium).is_file():
                raise SystemExit("--smoke requires a real PDFium library")
            cargo = os.environ.get("CARGO", "cargo")
            run([cargo, "build", "--locked"], ROOT / "rust", project / "cargo.log")
            names = {"Darwin": "libotter_core.dylib", "Linux": "libotter_core.so", "Windows": "otter_core.dll"}
            target = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "rust/target"))
            if not target.is_absolute():
                target = ROOT / "rust" / target
            native = target / "debug" / names[platform.system()]
            run([dart, "run", "bin/verify_bridge.dart", str(native), str(pdfium),
                 str(ROOT / "rust/tests/fixtures/two_pages.pdf")], project, project / "ffi.log")
            print((project / "ffi.log").read_text().strip())
    print(project)


if __name__ == "__main__":
    main()
