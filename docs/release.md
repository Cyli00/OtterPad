# 版本发布

当前分发 Android ARM64/ARMv7 APK、Windows x64 安装器与免安装便携版，以及 macOS（Apple 芯片）DMG；Linux 桌面端尚未提供。发布页采用「更新摘要 → 架构下载表 → 校验文件与完整变更」的顺序，参考 FlClash 的发布格式。

## 代码与工作流

- `pubspec.yaml` 是版本与构建号的唯一来源；`v0.1.5` 对应 `0.1.5+6`。
- `CHANGELOG.md` 按版本维护新增、优化、修复与升级说明。
- `.github/workflows/checks.yml` 共用于 CI 和 Release，固定 Flutter 3.44.6。检查在 Windows runner 上运行；Release 的构建矩阵为 Android（Linux runner）、Windows、macOS 三平台并行。
- `scripts/prepare_release.sh` 校验 tag、构建号及更新说明，生成 `build/release-preview/notes.md`。正式 tag 的构建号必须高于上个可达发布版本。
- `UpdateService` 使用现有 `device_info_plus` 的 Android ABI 列表选择安装包。无法读取 ABI 或无兼容包时，更新入口转向发布页。
- 根目录 `test/` 是被 Git 忽略的本地回归集；CI 不依赖这些未提交文件。提交扫描及其合成测试位于 `scripts/`，在 CI 中执行。

## 本地准备

1. 将版本改为下一个发布版本，递增构建号，补齐 `CHANGELOG.md`。
2. 运行 `bash scripts/prepare_release.sh v0.1.5` 并阅读生成的说明。
3. 按改动范围运行必要验证；最终 CI 会统一执行静态分析和敏感信息检查。
4. 核对发布提交包含所有源码、生成的国际化代码及发布资源。tag 无法包含未提交文件。

## 构建与发布

Release 工作流先执行共用检查，再按同一版本并行构建三个平台，产物汇总到同一目录后统一生成 `SHA256SUMS`。普通 CI 的 APK 使用测试签名，不作为正式分发包。

正式构建使用 Actions 已有的 `ANDROID_KEYSTORE_BASE64` 和 `ANDROID_KEY_PROPERTIES` 配置；必须沿用上个发布版本的签名证书。缺失配置会立即失败，不会回落到测试签名。

桌面端固定使用 `fastforge 0.6.12`，复用现有 Windows EXE 和 macOS DMG 配置。Windows 需要 Inno Setup，macOS 需要 appdmg。版本号直接读取 `pubspec.yaml`；产物按版本和构建号的确定路径收集，避免误取应用本体或旧安装包。macOS 打包前检查 runner 为 arm64。

Windows 本地构建（Git Bash）：

```bash
dart pub global activate fastforge 0.6.12
flutter pub get --enforce-lockfile
# Inno Setup 6.7.3 默认不附带简体中文，缺失时打包器会跳过 zh。
inno_dir=${INNO_SETUP_PATH:-'C:/Program Files (x86)/Inno Setup 6'}
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/1ff90acc4ed4aee82b1cda43253243deee3daed4/ChineseSimplified.isl \
  --output "$inno_dir/Languages/ChineseSimplified.isl"
CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS \
  dart pub global run fastforge:main package --platform windows --targets exe,zip --skip-clean
```

若 Inno Setup 安装在非默认目录，设置 `INNO_SETUP_PATH` 为包含 `ISCC.exe` 的目录。`fastforge` 命令映射到包内的 `main.dart`，因此 `dart pub global run` 使用 `fastforge:main`。`--skip-clean` 保留本地构建缓存。0.1.5 的原始产物为 `dist/0.1.5+6/otter_pad-0.1.5+6-windows-setup.exe` 和同目录下的 `otter_pad-0.1.5+6-windows.zip`。

Windows 阅读器需要 WebView2 Runtime；Windows 10 设备可能需要先安装 [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。便携版仅表示免安装，资料与设置仍保存在系统应用数据目录。

macOS 包目前不做代码签名与公证（`CODE_SIGN_IDENTITY` 为 ad-hoc），因此用户首次打开需要手动放行。要消除这一步，需 Apple Developer Program 账号并改为 Developer ID 签名 + 公证，可参照 `ios-testflight` job 的密钥注入方式。

在完成所需授权后，可手动触发 Release 工作流演练。`workflow_dispatch` 只上传 `dist-*` 和 `release-notes` 产物，即使选择 tag 也不会发布。只有推送 `v*` tag 才创建 GitHub Release；任何检查或构建失败都会阻止发布。改动桌面端打包配置后，务必先跑一次 `workflow_dispatch` 演练再打 tag。

## 0.1.5 发包前验收

- 使用正式候选包覆盖安装 `v0.1.4`，确认版本为 `0.1.5`、构建号为 `6`、签名一致。
- 确认 schema 1 → 2 后文献、标注、收藏、历史和设置仍可使用；保留升级前的完整备份。
- 在 ARM64 和 ARMv7 设备验证启动、PDF 阅读、中文检索及对应架构的更新包选择。
- 走通 PDF 导入/下载、解析、正文与图注翻译，以及一次备份恢复。
- Windows：用安装器安装并确认桌面/开始菜单快捷方式、卸载项正常，同时验证便携版解压即用；确认设置页能保存凭据（走 DPAPI）。
- macOS：从 DMG 拖入「应用程序」后放行打开，确认沙箱下出站网络可用（AI 与元数据请求）、阅读器本地 HTTP 服务可加载 HTML/图片、导入导出文件对话框可用。
- 验收通过后，再给同一个提交打 `v0.1.5` 并按仓库确认流程推送。

远端工作流、正式签名和设备覆盖安装需要实际执行后才能记为通过；本地分析及单元测试不能替代这些验收。
