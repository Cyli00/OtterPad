---
name: flutter-newui-design
description: 设计与实现 OtterPad 新 UI（纸白·石墨）的内容页、表单与浮层，并维护其分端示例（简称 flutter-new-design）。用于新增或改造这类界面，或调整新 UI 组件规范。
---

# OtterPad 新 UI：纸白 · 石墨

新 UI 是**内容页与表单**的一套独立规范：中性纸白／石墨配色、系统 sans 默认、紧凑排版、纯图标标题动作。应用导航、窗口外壳、阅读器工具栏不属于它，见[迁移范围](references/migration.md)。核对新 UI 视觉时不使用旧 `flutter-design`。

## 基准与真源

- 可运行基准：[基础组件页](examples/ai_settings/lib/default_widgets_demo.dart)；量化 Token 真源：[paper_theme.dart](examples/ai_settings/lib/paper_theme.dart)。
- 示例含 AI 设置、数据管理、基础组件、外观验证四页，每页同时展示桌面、Xiaomi 15、iPhone 17 Pro，只用内存数据、不代替生产 provider。运行与截图入口见[示例说明](examples/ai_settings/README.md)。
- 早期 AI 设置原型只提供方向，不作为 1:1 复刻目标。

## 按需读取

| 要做的事 | 读 |
|---|---|
| 选颜色、定字号／间距／图标尺寸、明暗与阅读纸面 | [references/tokens.md](references/tokens.md) |
| 做或改标题行、字段、卡片、分段、对话框、收藏夹 | [references/components.md](references/components.md) |
| 把新 UI 落进生产界面 | [references/migration.md](references/migration.md) |
| 跑示例、看三端截图、验收 | [references/verification.md](references/verification.md) |

## 工作方式

- 新组件或新规则要落进可操作示例；示例是规范的可执行证据。
- 复用已有业务状态、路由与浮层宿主，不为统一外观重写正常业务。
- 保留用户已有的模型卡片、角色分组与标题动作改法。

## 可以直接做

示例的构建、Widget 测试与 localhost 浏览器检查都是本地可丢弃操作：产物落在 `build/`，不读生产凭据，只连 127.0.0.1。直接跑、修、重跑，不必逐次确认。

## 完成标准

一次新 UI 改动完成 = 示例构建通过（静态分析 + Widget 测试 + release Web 构建）+ 三端视口截图看过并确认 + 受影响的规范与示例同步更新。只写完代码、没跑构建与截图就交回，算未完成。
