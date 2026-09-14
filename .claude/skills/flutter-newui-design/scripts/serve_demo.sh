#!/usr/bin/env bash
set -euo pipefail
skill_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$skill_root/../../.." && pwd)"
site="${1:-$repo_root/build/flutter-newui-design/site}"
if [ ! -f "$site/demo.html" ]; then
  printf '%s\n' '请先运行 build_demo.sh。' >&2
  exit 1
fi
printf '%s\n' '打开 http://127.0.0.1:8123/demo.html；Ctrl+C 停止。'
uv run --no-project python -X utf8 "$skill_root/scripts/serve_demo.py" "$site"
