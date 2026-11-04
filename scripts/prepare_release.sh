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

# 只认 v* 发布 tag，避免把 CI 测试 tag 当成上一个发布版本
previous_tag=$(git describe --tags --abbrev=0 --match 'v*' HEAD^)
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

# 同一版本内用标记分成英文、中文更新说明。发布正文固定为：
# 英文安装包 → 英文更新说明 → 中文更新说明。安装包只出现一次。
notes_dir=$(mktemp -d)
trap 'rm -rf "$notes_dir"' EXIT
: > "$notes_dir/en.md"
: > "$notes_dir/zh.md"
printf '%s\n' "$summary" | awk -v en="$notes_dir/en.md" -v zh="$notes_dir/zh.md" '
  function fail(message) {
    print message > "/dev/stderr"
    exit 2
  }
  /^<!-- release:en -->[[:space:]]*$/ {
    if (mode != "") fail("<!-- release:en --> 必须写在 <!-- release:zh --> 之前，且只能出现一次。")
    mode = "en"
    next
  }
  /^<!-- release:zh -->[[:space:]]*$/ {
    if (mode != "en") fail("<!-- release:zh --> 必须紧接在英文说明之后。")
    mode = "zh"
    next
  }
  mode == "" {
    if ($0 !~ /^[[:space:]]*$/) fail("版本说明必须从 <!-- release:en --> 开始。")
    next
  }
  mode == "en" { print > en; next }
  mode == "zh" { print > zh; next }
'
strip_edges() {
  awk '
    { lines[NR] = $0 }
    END {
      start = 1
      while (start <= NR && lines[start] ~ /^[[:space:]]*$/) start++
      end = NR
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i = start; i <= end; i++) print lines[i]
    }
  '
}
en_notes=$(strip_edges < "$notes_dir/en.md")
zh_notes=$(strip_edges < "$notes_dir/zh.md")
if [[ -z "${en_notes//[[:space:]]/}" || -z "${zh_notes//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md 的 $version 需要同时包含英文和中文更新说明。" >&2
  exit 1
fi

mkdir -p "$output_dir"
repository=${GITHUB_REPOSITORY:-Cyli00/OtterPad}
sed -e "s|VERSION|$version|g" \
    -e "s|REPOSITORY|$repository|g" \
    -e "s|PREVIOUS_TAG|$previous_tag|g" \
    .github/release_template.md > "$output_dir/notes.md"
{
  printf '\n## Changes\n\n%s\n\n## 更新内容\n\n%s\n' "$en_notes" "$zh_notes"
} >> "$output_dir/notes.md"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'version=%s\nbuild-number=%s\n' "$version" "$build_number" >> "$GITHUB_OUTPUT"
fi
printf '版本：%s+%s；上次发布：%s；说明：%s/notes.md\n' "$version" "$build_number" "$previous_tag" "$output_dir"
