#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
tag=${1:-}
output_dir=${2:-build/release-preview}
version_line=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '\r')
if [[ ! "$version_line" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)\+([1-9][0-9]*)$ ]]; then
  echo 'pubspec.yaml 必须包含带构建号的版本，例如 0.2.0+6。' >&2
  exit 1
fi
version=${BASH_REMATCH[1]}
build_number=${BASH_REMATCH[3]}
if [[ -n "$tag" && "$tag" != "v$version" ]]; then
  echo "tag $tag 与应用版本 v$version 不一致。" >&2
  exit 1
fi

previous_tag=$(git describe --tags --abbrev=0 HEAD^)
previous_version=$(git show "${previous_tag}:pubspec.yaml" | sed -n 's/^version:[[:space:]]*//p' | tr -d '\r')
previous_build=${previous_version##*+}
if [[ -n "$tag" ]] && { [[ ! "$previous_build" =~ ^[1-9][0-9]*$ ]] || (( build_number <= previous_build )); }; then
  echo "构建号必须高于 $previous_tag 的构建号。" >&2
  exit 1
fi

summary=$(awk -v heading="## [$version]" '
  { sub(/\r$/, "") }
  $0 == heading { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md)
if [[ -z "${summary//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md 缺少 $version 的更新说明。" >&2
  exit 1
fi

mkdir -p "$output_dir"
printf '%s\n\n' "$summary" > "$output_dir/notes.md"
repository=${GITHUB_REPOSITORY:-Cyli00/OtterPad}
sed -e "s|VERSION|$version|g" \
    -e "s|REPOSITORY|$repository|g" \
    -e "s|PREVIOUS_TAG|$previous_tag|g" \
    .github/release_template.md >> "$output_dir/notes.md"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'version=%s\nbuild-number=%s\n' "$version" "$build_number" >> "$GITHUB_OUTPUT"
fi
printf '版本：%s+%s；上次发布：%s；说明：%s/notes.md\n' "$version" "$build_number" "$previous_tag" "$output_dir"
