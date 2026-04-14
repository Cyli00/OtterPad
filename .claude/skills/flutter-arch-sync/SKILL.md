---
name: flutter-arch-sync
description: 自动同步 Flutter 项目架构文档。每当 Claude Code 完成代码编辑并通过检查后，检测 pubspec.yaml 的包依赖变化，分析受影响的代码，将架构和服务变更更新到 CLAUDE.md 的基础架构部分。适用于任何 Flutter/Dart 项目中的代码修改、包添加/删除/升级、重构、新增模块等场景。只要代码编辑通过了检查（lint、build、test），就应触发此技能。
---

# Flutter 架构文档自动同步

## 禁令

- 此技能 **只读源码、只写 CLAUDE.md**。禁止修改任何 `.dart`、`pubspec.yaml`、配置文件或其他非文档文件。
- 禁止执行 `flutter pub get`、`dart run`、`git commit`、`git push`、`rm`、`mv` 等有副作用的命令。允许的命令仅限 `git diff`、`grep`、`cat`、`find`。
- 禁止删除 CLAUDE.md 中与本次包变动无关的已有内容。
- 若 CLAUDE.md 不存在，仅在文件末尾追加 `## 基础架构` 段落，不创建新文件。

## 行格式

基础架构段落中每行严格遵循：

```
**模块名** (路径) — 能力/入口。约束/禁令。
```

- 模块名：简短中文功能名（如 `状态管理`、`网络层`）
- 路径：相对于项目根目录
- 约束/禁令：若无则写"无特殊约束"

**示例：**

```
**状态管理** (lib/providers/) — Riverpod 全局状态，ProviderScope 注入。禁止在 Widget 外直接读取 ref。
**网络层** (lib/services/api/) — Dio HTTP 客户端，统一拦截器。所有请求通过 ApiService，禁止直接实例化 Dio。
```

## 流程

代码编辑通过检查后执行：

1. `git diff HEAD -- pubspec.yaml`，无变动则结束。
2. 从 diff 提取变动的包名及类型（added / removed / changed）。
3. `grep -rl "package:<包名>/" lib/` 找到引用文件，阅读理解其架构角色。新增包若无 import，用 `git diff HEAD --name-only -- "lib/"` 从本次改动文件推断用途。
4. 更新 CLAUDE.md 的 `## 基础架构` 段落：新增包加行，删除包移行，升级包仅在能力变化时改行。保持功能分类顺序。
5. 简要输出：包变动列表 + 文档修改摘要。
