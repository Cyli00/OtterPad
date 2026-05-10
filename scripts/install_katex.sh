#!/usr/bin/env bash
set -euo pipefail

KATEX_VERSION="${KATEX_VERSION:-0.16.11}"
SKIP_FLUTTER_PUB_GET="${SKIP_FLUTTER_PUB_GET:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$REPO_ROOT/assets/katex"
CONTRIB_DIR="$TARGET_DIR/contrib"
FONTS_DIR="$TARGET_DIR/fonts"
DOWNLOAD_URL="https://github.com/KaTeX/KaTeX/releases/download/v${KATEX_VERSION}/katex.tar.gz"
TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="$TMP_DIR/katex.tar.gz"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "错误：$*" >&2
  exit 1
}

download_archive() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "$ARCHIVE_PATH" "$DOWNLOAD_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$ARCHIVE_PATH" "$DOWNLOAD_URL"
  else
    fail "需要安装 curl 或 wget 后再运行。"
  fi
}

find_required_file() {
  local file_name="$1"
  local file_path

  file_path="$(find "$TMP_DIR" -type f -name "$file_name" -print -quit)"
  [[ -n "$file_path" ]] || fail "下载包中缺少 $file_name。"
  printf '%s\n' "$file_path"
}

[[ -f "$REPO_ROOT/pubspec.yaml" ]] || fail "请把脚本放在仓库 scripts/ 目录下运行。"
command -v tar >/dev/null 2>&1 || fail "需要安装 tar 后再运行。"

echo "下载 KaTeX v${KATEX_VERSION}..."
download_archive

echo "解压资源..."
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

KATEX_CSS="$(find_required_file "katex.min.css")"
KATEX_JS="$(find_required_file "katex.min.js")"
AUTO_RENDER_JS="$(find_required_file "auto-render.min.js")"
FONT_COUNT="$(find "$TMP_DIR" -type f -path '*/fonts/*.woff2' | wc -l | tr -d ' ')"
[[ "$FONT_COUNT" -gt 0 ]] || fail "下载包中没有找到 woff2 字体。"

mkdir -p "$CONTRIB_DIR" "$FONTS_DIR"

# 只清理脚本安装的运行时文件，保留 README.md 和 .gitkeep 等仓库文件。
rm -f "$TARGET_DIR/katex.min.css" "$TARGET_DIR/katex.min.js" "$CONTRIB_DIR/auto-render.min.js"
find "$FONTS_DIR" -maxdepth 1 -type f -name '*.woff2' -delete

cp "$KATEX_CSS" "$TARGET_DIR/katex.min.css"
cp "$KATEX_JS" "$TARGET_DIR/katex.min.js"
cp "$AUTO_RENDER_JS" "$CONTRIB_DIR/auto-render.min.js"

while IFS= read -r font_path; do
  cp "$font_path" "$FONTS_DIR/"
done < <(find "$TMP_DIR" -type f -path '*/fonts/*.woff2' | sort)

INSTALLED_FONT_COUNT="$(find "$FONTS_DIR" -maxdepth 1 -type f -name '*.woff2' | wc -l | tr -d ' ')"
echo "已安装：katex.min.css、katex.min.js、auto-render.min.js、${INSTALLED_FONT_COUNT} 个 woff2 字体。"

if [[ "$SKIP_FLUTTER_PUB_GET" == "1" ]]; then
  echo "已跳过 flutter pub get。"
elif command -v flutter >/dev/null 2>&1; then
  echo "执行 flutter pub get..."
  (cd "$REPO_ROOT" && flutter pub get)
else
  echo "未找到 flutter，已跳过 flutter pub get。请稍后在仓库根目录手动执行。"
fi

echo "KaTeX 离线资源安装完成。"
