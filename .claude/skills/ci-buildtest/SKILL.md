---
name: ci-buildtest
description: 推送指定分支并触发 GitHub Actions CI 构建测试（静态分析、测试、Android APK）。平时 push 不构建，需要对某个分支跑一次构建时调用。
argument-hint: "[branch]"
disable-model-invocation: true
---

# CI 构建测试

`.github/workflows/ci.yml` 只在推送 `ci-*` tag 时运行，push 分支本身不会构建。本 skill 用脚本完成推送与打 tag。

在仓库根目录运行，参数是要测试的分支，省略时用当前分支：

```bash
bash .claude/skills/ci-buildtest/scripts/push_test_tag.sh $ARGUMENTS
```

脚本依次：快进推送分支 → 在该分支最新提交上推送 `ci-<UTC 时间>-<分支>` tag → 远端只保留最近 5 个 `ci-*` tag → gh 已登录时输出这次构建的链接。

- 推送被拒绝（远端有新提交）时，把错误转告用户并停下，不强推，也不自动 rebase 或 merge。
- 只有已提交的内容会进入构建；脚本提示有未提交改动时，转告用户。
- 用户要等结果时用 `gh run watch <run-id>` 跟踪；没要求就不等。
- 正式发布用 `v*` tag，走 `release.yml`，不归本 skill 管。
