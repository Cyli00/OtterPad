"""Compare real OCR inputs against the read-only v0.1.7 Dart structure parser."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def first_difference(left, right, path="$structure"):
    if isinstance(left, dict) and isinstance(right, dict):
        if left.keys() != right.keys():
            return path + " (keys)"
        for key in left:
            difference = first_difference(left[key], right[key], path + "." + key)
            if difference:
                return difference
        return None
    if isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            return path + " (length)"
        for index, (a, b) in enumerate(zip(left, right)):
            difference = first_difference(a, b, f"{path}[{index}]")
            if difference:
                return difference
        return None
    return None if left == right else path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--dart", required=True, help="Dart SDK binary (not Flutter wrapper)")
    parser.add_argument("--cargo", default="cargo")
    parser.add_argument("--figure-reference", type=Path,
                        help="Figure JSON emitted by the v0.1.7 findFigures reference")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    reference = subprocess.check_output(
        ["git", "show", "v0.1.7:lib/services/document_structure.dart"], cwd=root
    )
    examples = ["--example", "structure_json"]
    if args.figure_reference:
        if len(args.inputs) != 1:
            parser.error("--figure-reference requires exactly one OCR input")
        examples += ["--example", "figure_json"]
    subprocess.run([args.cargo, "build", "--locked", "--offline", *examples],
                   cwd=root / "rust", check=True)
    executable = root / "rust/target/debug/examples/structure_json"
    if __import__("os").name == "nt":
        executable = executable.with_suffix(".exe")
    with tempfile.TemporaryDirectory(prefix="otter-ocr-reference-") as directory:
        directory = Path(directory)
        (directory / "reference.dart").write_bytes(reference)
        driver = directory / "driver.dart"
        driver.write_text("""import 'dart:io';
import 'dart:convert';
import 'reference.dart';
void main(List<String> args) {
  print(jsonEncode(DocumentStructure.parse(File(args.single).readAsStringSync()).toJson()));
}
""")
        for index, source in enumerate(args.inputs):
            source = source.resolve()
            dart = json.loads(subprocess.check_output([args.dart, str(driver), str(source)]))
            rust = json.loads(subprocess.check_output([str(executable), str(source)]))
            difference = first_difference(dart, rust)
            if difference:
                raise SystemExit(f"input {index + 1}: differs at {difference}")
            pages = dart["layoutParsingResults"]
            count = sum(len(p["prunedResult"]["parsing_res_list"]) for p in pages)
            print(f"input {index + 1}: {len(pages)} pages, {count} blocks match v0.1.7")
            if args.figure_reference:
                figure_executable = executable.with_name("figure_json" + executable.suffix)
                expected = json.loads(args.figure_reference.read_text())
                actual = json.loads(subprocess.check_output([str(figure_executable), str(source)]))
                difference = first_difference(expected, actual, "$figures")
                if difference:
                    raise SystemExit(f"figure ownership differs at {difference}")
                print(f"{len(actual)} figures: captions, members, and source ranges match v0.1.7")


if __name__ == "__main__":
    main()
