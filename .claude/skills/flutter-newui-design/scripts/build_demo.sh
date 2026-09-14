#!/usr/bin/env bash
set -euo pipefail
skill_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$skill_root/../../.." && pwd)"
output="${1:-$repo_root/build/flutter-newui-design}"
example="$skill_root/examples/ai_settings"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
app="$output/app"
if [ ! -f "$app/web/index.html" ]; then
  flutter create --platforms web --empty --no-pub --project-name newui_ai_demo "$app"
fi
cp -R "$example/lib" "$example/test" "$app/"
cp "$example/pubspec.yaml" "$example/l10n.yaml" "$example/analysis_options.yaml" "$app/"
(
  cd "$app"
  flutter pub get
  flutter gen-l10n
  flutter analyze --no-pub lib test
  flutter test test --no-pub
  flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
)
mkdir -p "$output/site"
cp -R "$app/build/web/." "$output/site/"
uv run --no-project python -X utf8 "$skill_root/scripts/build_previews.py" "$output/site"
