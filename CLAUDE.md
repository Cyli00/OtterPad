# Project Guidelines

## Edit Rules

- 每次更换 Infrastructure Modules 内部依赖，必须同步更新该模块。
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 平台生成目录。

## Compact/Handoff Rules

- 优先压缩基于检索推理的 Flutter 任务，而非预训练知识。

## Behavior

### 代码原则
- 不写没要求的功能、抽象和灵活性；200 行能用 50 行搞定就重写。
- 不顺手改相邻代码，不重构没坏的东西；每一行改动都要能对应到用户需求。
- 自己产生的孤儿代码必须清理；无关的死代码只提醒，不擅自删。
- 多步任务先列计划（步骤 → 验证方式），有疑问在动手前问清楚。

### 沟通与总结
- **先给结论**：一句话先说清楚结果和影响，再展开具体内容。
- **顺着事情讲**：按“为什么改 → 怎么改的 → 现在如何”连贯说明，别甩一堆零碎散点让读者自己拼。
- **直接给主意**：提建议直接给最推荐的做法和理由，别抛一堆选项让人纠结；确需选择时最多给两个。
- **带出下一步**：结尾明确给出一个具体的下一步动作，别含糊发散。

## UI / Animation Design

- 视觉、动效、触觉与多端设计规范严格遵循 `flutter-design` skill (`.claude/skills/flutter-design/SKILL.md`)。

## Multilanguage (i18n)

- 用户可见文本必须 ARB 国际化（`lib/l10n/app_en.arb` / `app_zh.arb`，改后 `flutter gen-l10n`）。
- Widget 层走 `context.l10n`，服务层走 `rootNavigatorKey.currentContext`。
- Prompt、正则、技术标识符、代码注释不进 i18n。

## Dependency

- 改动 `pubspec.yaml` 必须先查 pub.dev 最新稳定版，禁止凭记忆填写。
