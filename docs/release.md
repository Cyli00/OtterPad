# 版本发布

当前分发 Android ARM64/ARMv7 APK、Windows x64 安装器与免安装便携版，以及 macOS（Apple 芯片）DMG；Linux 桌面端尚未提供。发布页采用「更新摘要 → 架构下载表 → 校验文件与完整变更」的顺序，参考 FlClash 的发布格式。

## 代码与工作流

- `pubspec.yaml` 是版本与构建号的唯一来源；`v0.1.6` 对应 `0.1.6+7`。
- `CHANGELOG.md` 按版本维护新增、优化、修复与升级说明。
- `.github/workflows/checks.yml` 共用于 CI 和 Release，固定 Flutter 3.44.6。检查在 Windows runner 上运行；Release 的构建矩阵为 Android（Linux runner）、Windows、macOS 三平台并行。
- `scripts/prepare_release.sh` 校验 tag、构建号及更新说明，生成 `build/release-preview/notes.md`。正式 tag 的构建号必须高于上个可达发布版本。
- `UpdateService` 使用现有 `device_info_plus` 的 Android ABI 列表选择安装包。无法读取 ABI 或无兼容包时，更新入口转向发布页。
- 根目录 `test/` 是被 Git 忽略的本地回归集；CI 不依赖这些未提交文件。提交扫描及其合成测试位于 `scripts/`，在 CI 中执行。

## Rust 工具链（0.2.0 起）

当前 Rust 后端独立编译。按用户最新安排，本轮后续只做逻辑迁移、格式化、FRB 绑定生成和编译，不再新增或执行测试；下述测试与应用验收交由统一安排，历史通过记录不代表最新修改已完成验证。工具链固定在 `rust/rust-toolchain.toml`：Rust `1.99.1`，组件 `rustfmt`、`clippy`。`rust/Cargo.lock` 随源码保存。

`checks.yml` 已增加 Linux、Windows、macOS 三个 runner 的原生 Rust 检查，CI 和 Release 通过共用检查自动引用。各 runner 在 `rust/` 下读取固定工具链，然后执行：

```bash
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

测试使用实际 SQLite/FTS5、进程内启动的本地 HTTP 服务和固定版本 PDFium，覆盖数据落盘/约束/迁移续传、OCR 与 AI 协议、流式取消、翻译缓存、会话兼容以及 PDF 渲染与字符几何。每个 CI runner 先通过 `scripts/fetch_pdfium.py --target host` 校验并解压二进制，设置 `PDFIUM_LIBRARY_PATH` 再运行测试。本机 PDFium 的手动准备示例：

```bash
export PDFIUM_LIBRARY_PATH="$(python3 scripts/fetch_pdfium.py --target host --output /tmp/otter-pdfium)"
cd rust
cargo test --locked
```

新增 CI 配置尚未在远端执行，本机只运行了 macOS arm64 的 Rust 检查；Linux、Windows 和 Android 不能据此认定通过。

FRB 的 Rust API 与生成绑定已加入；Dart 绑定在独立临时工程中验证，未写入应用。Windows 检查 job 增加固定版本 `flutter_rust_bridge_codegen 2.13.0`、`cargo-expand 1.0.127`，执行：

```bash
python scripts/generate_rust_bridge.py --check-rust --smoke
```

该命令重建 Rust 绑定并比较差异，在仓库外生成 Dart 类型，运行 Freezed、`dart analyze`，构建真实原生动态库，再由 Dart 走通 SQLite/FTS、错误码、PDFium、OCR HTTP/Stream、锚点/笔记/会话及备份恢复。需要 `PDFIUM_LIBRARY_PATH` 指向已校验的宿主动态库；`--verify` 只做类型与分析器检查。脚本不会修改应用的 `pubspec.yaml`、`lib/` 或平台目录。本机完整 FFI 已运行，新增远端步骤尚未执行。

cargokit 与 Flutter 应用构建尚未接入，应用接入仍需补齐：

- 在构建 job 安装对应 target：Android `aarch64-linux-android`、`armv7-linux-androideabi`（另需 NDK），Windows `x86_64-pc-windows-msvc`，macOS `aarch64-apple-darwin`；配置 Cargo 缓存。
- 修改 `rust/src/api/` 后运行上述生成器，将 Rust 绑定与源码一起保存；本轮前端排除，Dart 产物只在临时工程保留。
- 随包携带固定 ABI 的 PDFium 动态库、校验值与许可，实际执行四个目标的 `flutter build`。

因此当前检查通过不代表 0.2.0 Flutter 包已可构建。

## 本地准备

1. 将版本改为下一个发布版本，递增构建号，补齐 `CHANGELOG.md`。
2. 运行 `bash scripts/prepare_release.sh v0.1.6` 并阅读生成的说明。
3. 按改动范围运行必要验证；最终 CI 会统一执行静态分析和敏感信息检查。
4. 核对发布提交包含所有源码、生成的国际化代码及发布资源。tag 无法包含未提交文件。

## 构建与发布

Release 工作流先执行共用检查，再按同一版本并行构建三个平台，产物汇总到同一目录后统一生成 `SHA256SUMS`。普通 CI 的 APK 使用测试签名，不作为正式分发包。

正式构建使用 Actions 已有的 `ANDROID_KEYSTORE_BASE64` 和 `ANDROID_KEY_PROPERTIES` 配置；必须沿用上个发布版本的签名证书。缺失配置会立即失败，不会回落到测试签名。

桌面端固定使用 `fastforge 0.6.12`，复用现有 Windows EXE 和 macOS DMG 配置。Windows 固定安装 Chocolatey 已收录的 Inno Setup 6.7.1，macOS 需要 appdmg。版本号直接读取 `pubspec.yaml`；产物按版本和构建号的确定路径收集，避免误取应用本体或旧安装包。macOS 打包前检查 runner 为 arm64。

macOS 构建通过 `FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET=11.0` 设置最低系统版本，满足 `gal` 的要求。Flutter 将该设置传给 Xcode，并同步到生成的 `FlutterGeneratedPluginSwiftPackage`；仅设置普通的 `MACOSX_DEPLOYMENT_TARGET` 环境变量不足以覆盖工程配置。本地 macOS 打包也需给 fastforge 命令设置此前缀。保留 Swift Package Manager，尚未支持它的插件由 Flutter 回退到 CocoaPods；相关兼容性警告不等同于本次最低系统版本冲突。

Windows 本地构建（Git Bash）：

```bash
dart pub global activate fastforge 0.6.12
flutter pub get --enforce-lockfile
# Inno Setup 6.7.1 默认不附带简体中文，缺失时打包器会跳过 zh。
inno_dir=${INNO_SETUP_PATH:-'C:/Program Files (x86)/Inno Setup 6'}
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/1ff90acc4ed4aee82b1cda43253243deee3daed4/ChineseSimplified.isl \
  --output "$inno_dir/Languages/ChineseSimplified.isl"
CL=-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS \
  dart pub global run fastforge:main package --platform windows --targets exe,zip --skip-clean
```

若 Inno Setup 安装在非默认目录，设置 `INNO_SETUP_PATH` 为包含 `ISCC.exe` 的目录。`fastforge` 命令映射到包内的 `main.dart`，因此 `dart pub global run` 使用 `fastforge:main`。`--skip-clean` 保留本地构建缓存。0.1.6 的原始产物为 `dist/0.1.6+7/otter_pad-0.1.6+7-windows-setup.exe` 和同目录下的 `otter_pad-0.1.6+7-windows.zip`。

`CL` 中的宏定义使用 MSVC 同样支持的 `-D` 写法。Git Bash 会把以 `/D` 开头的环境变量值误转为 Windows 路径，导致 CMake 的编译器识别失败并报 `No CMAKE_CXX_COMPILER could be found`；此时并不一定缺少编译器。

0.1.x 的 Windows 阅读器依赖 WebView2 Runtime，0.2.0 起不再需要。便携版仅表示免安装，资料与设置仍保存在系统应用数据目录。

macOS 包目前不做代码签名与公证（`CODE_SIGN_IDENTITY` 为 ad-hoc），因此用户首次打开需要手动放行。要消除这一步，需 Apple Developer Program 账号并改为 Developer ID 签名 + 公证，可参照 `ios-testflight` job 的密钥注入方式。

在完成所需授权后，可手动触发 Release 工作流演练。`workflow_dispatch` 只上传 `dist-*` 和 `release-notes` 产物，即使选择 tag 也不会发布。只有推送 `v*` tag 才创建 GitHub Release；任何检查或构建失败都会阻止发布。改动桌面端打包配置后，务必先跑一次 `workflow_dispatch` 演练再打 tag。

## 0.2.0 发包前验收

- 用正式候选包覆盖安装 `v0.1.7`（含文献、标注、译文、问 AI 会话、收藏、Zotero 映射的真实数据），确认签名一致、迁移完成，逐项对照 `docs/architecture.md` 的迁移表；中途杀进程后重启能续迁。
- 迁移后 0.1.x 目录仍在，存储设置能手动清理；用 0.1.x 备份压缩包能恢复。
- 在 ARM64 和 ARMv7 设备、Windows x64、macOS Apple 芯片上验证启动、长 PDF 翻页缩放、重排正文的滚动与分页切换、中文检索、标注。
- 走通 PDF 导入、解析、全文与题注翻译、问 AI，以及一次备份恢复。
- Windows：安装器与便携版都能启动，凭据保存正常（DPAPI）。macOS：DMG 安装后放行打开，沙箱内出站网络、文件导入导出可用。
- 验收通过后，再给同一个提交打 `v0.2.0` 并按仓库确认流程推送。

远端工作流、正式签名和设备覆盖安装需要实际执行后才能记为通过；本地分析及单元测试不能替代这些验收。
