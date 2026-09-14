# 版本发布

当前分发 Android ARM64 与 ARMv7 APK。发布页采用「更新摘要 → 架构下载表 → 校验文件与完整变更」的顺序，参考 FlClash 的发布格式。

## 代码与工作流

- `pubspec.yaml` 是版本与构建号的唯一来源；`v0.2.0` 对应 `0.2.0+6`。
- `CHANGELOG.md` 按版本维护新增、优化、修复与升级说明。
- `.github/workflows/checks.yml` 共用于 CI 和 Release，固定 Flutter 3.44.6。检查在 Windows runner 上运行；Android 构建在 Linux runner 上运行。
- `scripts/prepare_release.sh` 校验 tag、构建号及更新说明，生成 `build/release-preview/notes.md`。正式 tag 的构建号必须高于上个可达发布版本。
- `UpdateService` 使用现有 `device_info_plus` 的 Android ABI 列表选择安装包。无法读取 ABI 或无兼容包时，更新入口转向发布页。
- 根目录 `test/` 是被 Git 忽略的本地回归集；CI 不依赖这些未提交文件。提交扫描及其合成测试位于 `scripts/`，在 CI 中执行。

## 本地准备

1. 将版本改为下一个发布版本，递增构建号，补齐 `CHANGELOG.md`。
2. 运行 `bash scripts/prepare_release.sh v0.2.0` 并阅读生成的说明。
3. 按改动范围运行必要验证；最终 CI 会统一执行静态分析和敏感信息检查。
4. 核对发布提交包含所有源码、生成的国际化代码及发布资源。tag 无法包含未提交文件。

## 构建与发布

Release 工作流先执行共用检查，再按同一版本构建两个 ABI 的 APK，并生成 `SHA256SUMS`。普通 CI 的 APK 使用测试签名，不作为正式分发包。

正式构建使用 Actions 已有的 `ANDROID_KEYSTORE_BASE64` 和 `ANDROID_KEY_PROPERTIES` 配置；必须沿用上个发布版本的签名证书。缺失配置会立即失败，不会回落到测试签名。

在完成所需授权后，可手动触发 Release 工作流演练。`workflow_dispatch` 只上传 `android-release` 和 `release-notes` 产物，即使选择 tag 也不会发布。只有推送 `v*` tag 才创建 GitHub Release；任何检查或构建失败都会阻止发布。

## 0.2.0 发包前验收

- 使用正式候选包覆盖安装 `v0.1.4`，确认版本为 `0.2.0`、构建号为 `6`、签名一致。
- 确认 schema 1 → 2 后文献、标注、收藏、历史和设置仍可使用；保留升级前的完整备份。
- 在 ARM64 和 ARMv7 设备验证启动、PDF 阅读、中文检索及对应架构的更新包选择。
- 走通 PDF 导入/下载、解析、正文与图注翻译，以及一次备份恢复。
- 验收通过后，再给同一个提交打 `v0.2.0` 并按仓库确认流程推送。

远端工作流、正式签名和设备覆盖安装需要实际执行后才能记为通过；本地分析及单元测试不能替代这些验收。
