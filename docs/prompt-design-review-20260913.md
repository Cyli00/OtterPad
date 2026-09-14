# Prompt 设计复审与改造（2026-09-13）

## 结论

按 OpenAI《Rethinking skills and prompts for GPT-6 Astra》复审并改造了 `lib/services/prompts.dart` 的全部
prompt 声明（现共 8 条）。真实收益只在翻译路径：**文档逐段翻译每次请求的默认文本从 1158 降到 646 字符（-44%）**，因为
`%%%%` 分段规则被改成按需追加的守卫。figure 修缮与问 AI 是**净增**字符，换的是两件事的正确性：
降级请求下的输出契约自足、文献依据边界不丢。

本轮（评审后）追加三处语义修正，并补了 7 个能真正跑出结论的测试。`flutter analyze` 无本次相关告警。

## 借用的标准，以及不借用的部分

文章讲的是 skill / AGENTS.md 的组织方式。只有三条对业务 system prompt 直接成立：

| # | 借用 | 不借用 |
|---|---|---|
| S1 | 规则之间别重复，重复即噪音 | 「描述要短到不被截断」是 skill 清单特有的约束 |
| S2 | 只在特定调用下成立的规则，别放进每次请求都带的那段 | 「最小路由 + 分册读取」是 skill 的文件机制，业务 prompt 没有等价物 |
| S3 | 为旧模型加的强硬话术要复核 | 「模型能处理歧义所以少写规则」不适用于关思考的结构化任务 |

**字符减少 ≠ 请求开销同比减少**：字段图例从 system prompt 搬到 user prompt 只是组织方式改善，
它每次请求照样发出。

## 终态改动（按文件）

### 1. `lib/services/prompts.dart`

| 改动 | 目的 |
|---|---|
| 翻译默认文本删掉 `%%%%` 规则；R2+R4 合并；6 条 → 4 条 | S2：该规则只对划词子选区成立；文档翻译每段都白带 |
| 翻译 R4：专有名词「一律保留原文」→「有通行译名就用，否则保留」 | S1：给出何时用/何时不用（**行为变更**） |
| 新增不可定制的 `Prompts.translationSegmentGuard` | 承接被移出的规则 |
| `chatSystem` 拆出两条并补回边界：本文结果/方法/数字若文档没有，必须明说，**不得把常识当作本文结论** | 上一版放宽过头削弱了文献依据要求 |
| `figureFixSystem` 规则 3 恢复脚注归属限制：解释性脚注**既不是图的 visual，也不是孤立 caption**，不得仅因字母开头被认领进图 | 上一版只保留了「不是孤立 caption」，丢掉了归属限制，可能把图题旁解释文字重新裁进图 |
| `figureFixSystem` 末尾补回完整输出契约（`figures[].caption_id/visual_ids/kind` + 两个数组 + `no coordinates`） | **schema 会降级**：`agent_chat_service.dart:104` 的 modes 阶梯为 openai/gemini `['schema','json']`、anthropic `['schema','none']`、兼容端 `['schema','json','none']`，400/422 时降级且不会把 schema 补进提示词，因此不能用「schema 里没这个字段」论证删除约束 |
| `figureFixSystem` 合并跨列/跨页两条规则；三种 tag 的枚举解释下沉到 user prompt | S1：去掉重复与可推导内容 |
| `kDefaultSummaryImagePrompt` 否定堆叠 → 正向锚点 + 集中禁止项 | 原 `no chaotic or dense text` 与 `no empty minimal look` 是同维度两端 |
| `PromptDef.placeholdersLabel` getter | 占位符清单单一真相 |

### 2. `lib/services/translation_service.dart`

`translate()`（第 79 行）与 `translateStream()`（第 167 行）各追加 3 行，仅在 `text.contains('%%%%')` 时拼接守卫。
副作用是修掉一个漏洞：守卫在不可定制区，用户改写自己的 system prompt 也不会丢多段约束。

### 3. `lib/pages/setting/translation_settings_section.dart`

新增 `_promptDesc()`，设置项说明的占位符清单改由 registry 渲染，ARB 不再手写占位符名。

### 4. `lib/l10n/app_en.arb` / `app_zh.arb` + `flutter gen-l10n` 生成物

去掉 `systemPromptDesc` / `userPromptDesc` 里硬编码的占位符名，新增 `promptPlaceholdersAvailable`。

### 5. 新增测试

- `test/services/translation_prompt_segmentation_test.dart`：用 `CapturingAdapter`（记录请求体 +
  强制 400）验证**在自定义 system prompt 下**，普通逐段翻译不追加守卫、划词多段追加且追加在用户
  prompt 之后；非流式与流式两条路径都覆盖。
- `test/services/prompt_contract_test.dart`：锁定三条不变量——figure 修缮 prompt 在降级模式下
  输出契约自足（六个键 + `no coordinates`）、脚注归属边界存在、翻译默认文本不含 `%%%%` 且守卫含之、
  问 AI 保留「不得把常识当作本文结论」。

## 实测每请求字符数（默认文本，非 token）

| 路径 | 改前 | 改后 | 变化 |
|---|---|---|---|
| 翻译（文档逐段，最热） | 1158 | 646 | **-44%** |
| 翻译（划词多段，含守卫） | 1158 | 953 | -18% |
| figure 修缮（system + inventory 图例） | 2325 | 2428 | +4%（净增，换降级可用性与脚注边界） |
| 问 AI（system，不含整篇文档） | 495 | 723 | +46%（相对注入的整篇文档可忽略） |
| 生图 | 648 | 676 | +4% |

## 行为变更与回滚

1. **术语/专有名词改用通行译名**，仅影响未自定义 system prompt 的用户。
   回滚：把翻译 R4 换回 `For content that should not be translated (such as proper nouns, code, formulas, etc.), keep the original text.`
2. 老用户的自定义 prompt 不会被覆盖（`PromptStore.resolve` 语义），划词多段翻译会额外收到守卫。

## 验证与未验证

已验证（本地跑通）：

- `flutter test` 4 个文件 13 项全过：本次新增的 7 项（分段守卫 3 + 契约 4）+ 既有的译文缓存、
  并发取消、标注锚点 6 项。
- `flutter analyze`：只剩 2 条与本次无关的既有 info（`test/services/chat_flow_test.dart`、
  `test/services/chat_markdown_test.dart`）；本次改动的文件无告警。
- `dart format`：本次改动文件已格式化。

**未验证**：prompt 文本改动对**模型实际行为**的影响（图块归属准确率、问 AI 是否会拿常识充当本文
结论）。这些需要真实 API 调用，本仓库的测试只覆盖到「发出去的 prompt 是什么」。
figure 修缮的归属准确率**本轮不另做回归**：该链路此前已实测过，本次 prompt 改动幅度小，按已测结论
继续沿用。

## 未执行 / 待决策

1. **`figure_fix_service.dart:250` 维持 `ThinkingLevel.off`**——已定：不取数据、按经验保留默认 off。
   若 off 下真出现归属偏差或 JSON 不合规，升级顺序为 **off → minimal → medium**。
   注意：该升级阶梯**目前没有实现**。现有机制只有 `AgentThinkingPayload` 的**厂商级**降级
   （模型不支持完全关思考时映射到该家最低档），没有「任务失败 → 抬高一档重试」的逻辑；
   `figure_fix_service` 解析失败直接抛错。要不要把阶梯做成自动重试，是独立决策（每次重试= 一次完整
   请求重发）。
2. `agent_chat_service` 的降级路径**系统性地不补 schema**：本次是在 figure 修缮的 prompt 里补自足
   契约（figureFix 是目前唯一 schema 调用方）。若将来出现第二个 schema 调用方，应考虑在降级分支
   统一注入完整输出契约。
3. `.agents/skills/flutter-design/SKILL.md` 516 行单体文档（这条是文章 S2 的原生地，值得做）。
4. `Prompts` 类里「可定制 / 不可定制」靠注释分区，建议拆类或加 `customizable` 字段。

## 注意：工作区存在与本次无关的未提交改动

`git status` 中除本次 5 个源文件 + 2 个测试 + 本文档外的大量 `M`（`debugBuildCacheKey` 等测试缝的删除、
格式重排、ARB 的 Zotero/导出键）**不是本次改动**，提交时别混入。`flutter gen-l10n` 重生成的 3 个
`app_localizations*.dart` 同时带上了既有 ARB 漂移。

## 下一步

无阻塞项，本轮可以收尾。唯一待你回一句的是：`figure_fix` 的 `off → minimal → medium` 升级阶梯
要不要做成**自动重试**（判据：解析失败／归属校验不过就抬一档重发）。不做的话，现有行为就是
保持 off、失败即报错，也完全自洽。
