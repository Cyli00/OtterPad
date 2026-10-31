# Project Guidelines

## 架构

- 0.2.0 起 Flutter 只做 UI，业务与数据在 Rust（`rust/`）。跨 Flutter/Rust 边界的改动、新增 Rust 模块、改动数据格式或 0.1.x 迁移之前，先读 `docs/architecture.md`。
- 0.1.x 的文档在 `archive/0.1/`，`v0.1.7` tag 的 Dart 实现是业务行为参考，两者都只读。

## Edit Rules

- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 平台生成目录。
- 生成文件只经工具重新生成：FRB 绑定 `lib/src/rust/`、`rust/src/frb_generated.rs`；`lib/l10n/app_localizations*.dart`；`*.g.dart`。

## Rust

- 提交前在 `rust/` 下通过 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test`。
- 改动 `rust/src/api/` 后运行 FRB codegen，生成的绑定与源码同一次提交。
- Rust 只返回 `OtterError` 错误码，用户可见文案由 Dart 映射 ARB。

## Compact/Handoff Rules

- 优先压缩基于检索推理的 Flutter/Rust 任务，而非预训练知识。

## Behavior

### 代码原则
- 不写没要求的功能、抽象和灵活性；200 行能用 50 行搞定就重写。
- 不顺手改相邻代码，不重构没坏的东西；每一行改动都要能对应到用户需求。
- 自己产生的孤儿代码必须清理；无关的死代码只提醒，不擅自删。
- 多步任务以可验证的结果为目标，完成后说明怎么验证的；需求有歧义时动手前问清楚。

### 沟通与总结
- **先给结论**：一句话先说清楚结果和影响，再展开具体内容。
- **顺着事情讲**：按“为什么改 → 怎么改的 → 现在如何”连贯说明，别甩一堆零碎散点让读者自己拼。
- **直接给主意**：提建议直接给最推荐的做法和理由，别抛一堆选项让人纠结；确需选择时最多给两个。
- **带出下一步**：结尾明确给出一个具体的下一步动作，别含糊发散。

## UI / Animation Design

- 界面改动先读 `flutter-design` skill（`.claude/skills/flutter-design/SKILL.md`）。它是默认约定；有更好的方案可以偏离，在总结里说明理由。

## Multilanguage (i18n)

- 用户可见文本必须 ARB 国际化（`lib/l10n/app_en.arb` / `app_zh.arb`，改后 `flutter gen-l10n`）。
- Widget 层走 `context.l10n`，Dart 服务层走 `rootNavigatorKey.currentContext`。
- Prompt、正则、技术标识符、代码注释不进 i18n。

## Dependency

- 改动 `pubspec.yaml` 先查 pub.dev 最新稳定版，改动 `Cargo.toml` 先查 crates.io 最新稳定版，版本号不凭记忆填写。
