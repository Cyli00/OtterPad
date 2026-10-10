#!/usr/bin/env bash
# 推送分支，并在其最新提交上推送 ci-* tag，触发 .github/workflows/ci.yml。
# 用法：bash push_test_tag.sh [branch]   省略 branch 时用当前分支
#       DRY_RUN=1 bash push_test_tag.sh dev   只打印将执行的推送，不改远端
set -euo pipefail

keep=5  # 远端保留的 ci-* tag 数

run() {
  if [[ "${DRY_RUN:-}" == 1 ]]; then echo "[dry-run] $*"; else "$@"; fi
}

cd "$(git rev-parse --show-toplevel)"
current=$(git branch --show-current)
branch=${1:-$current}
if [[ -z "$branch" ]]; then
  echo "当前处于 detached HEAD，请指定要测试的分支。" >&2
  exit 1
fi
if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
  echo "本地没有分支 $branch。" >&2
  exit 1
fi
if [[ "$branch" == "$current" && -n "$(git status --porcelain)" ]]; then
  echo "提示：工作区有未提交的改动，它们不会进入这次构建。" >&2
fi

# 只做快进推送；远端有新提交时 git 会拒绝，脚本随之停止，不强推
run git push origin "refs/heads/$branch:refs/heads/$branch"

sha=$(git rev-parse "refs/heads/$branch")
slug=$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '-')
# 时间戳在前：按名字排序即按时间排序；GitHub 的 tag 过滤 * 不匹配 /，分支名里的 / 已换成 -
tag="ci-$(date -u +%Y%m%d-%H%M%S)-$slug"
run git push origin "$sha:refs/tags/$tag"
echo "$([[ "${DRY_RUN:-}" == 1 ]] && echo 将推送 || echo 已推送) $branch（${sha:0:7}），触发 tag：$tag"

# 远端只保留最近 $keep 个 ci-* tag
mapfile -t stale < <(
  git ls-remote --tags --refs origin 'refs/tags/ci-*' | awk '{print $2}' | sort | head -n -"$keep"
)
if (( ${#stale[@]} > 0 )); then
  run git push --quiet origin --delete "${stale[@]}"
  echo "已清理 ${#stale[@]} 个旧 ci-* tag。"
fi

repo=$(git remote get-url origin)
repo=${repo%.git}
repo=${repo/git@github.com:/https://github.com/}
if [[ "${DRY_RUN:-}" != 1 ]] && command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  # GitHub 登记这次 run 通常需要几秒
  for _ in 1 2 3 4 5 6; do
    url=$(gh run list --workflow ci.yml --limit 20 --json url,headBranch \
      --jq ".[] | select(.headBranch == \"$tag\") | .url" | head -n 1)
    if [[ -n "$url" ]]; then
      echo "构建：$url"
      exit 0
    fi
    sleep 5
  done
fi
echo "构建列表：$repo/actions/workflows/ci.yml"
