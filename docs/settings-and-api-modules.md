# 设置与 API 模块

AI 与 OCR 配置分别由 `providers/agent_api_provider.dart` 和 `providers/doc_extract_api_provider.dart` 管理。原 `api_provider.dart` 的调用点已迁移，不再保留混合入口。拆分沿用原有设置键、凭据槽、服务商 ID、模型参数序列化和枚举顺序。

| 文件 | 职责 |
| --- | --- |
| `data/models/ai/agent_protocol.dart` | AI 协议、默认端点与 URL 规则 |
| `data/models/ai/agent_config.dart` | 服务商实例、模型参数与解析后的配置数据 |
| `data/models/ai/agent_model_capability.dart` | 模型能力数据、序列化与无缓存的推断规则 |
| `data/models/ocr/doc_extract_config.dart` | OCR 提供商、解析选项与配置数据 |
| `services/model_capability_store.dart` | 远程能力缓存，以及 `AgentProviderCapabilities` 扩展的能力查询 |

纯数据模块不依赖 Riverpod、存储或服务。需要加载配置或修改设置的调用点依赖对应 provider；只消费配置的请求构造、结果转换等服务直接依赖数据模块。能力查询沿用“用户手动设置 → 远程能力表 → 默认推断”的顺序，调用 `capabilityFor` 时显式导入能力缓存服务。

## 文案与设置控件

提供商配置按槽独立保存 API Key / Token，切换提供商时不清空其他提供商的输入。用量仅在没有远程配额查询接口时采用本地记账估算，界面需明确标识估算及配额性质；这些行为约束由本模块维护，不放入 UI 设计 skill。

备份恢复枚举只保留业务语义，界面通过 `context.l10n` 取得名称与说明。阅读器主题、字体、翻页方式和译文样式的展示映射放在 `l10n/reader_labels.dart`。历史分组保存日期类别及月份，月份由 ARB 的 `DateTime` 格式按当前语言显示；切换语言不需要重建历史数据。文库重建进度按项目约定从根导航上下文取得本地化文案。

`core/app_theme.dart` 统一生成明暗主题，并提供滑块的尺寸配置。阅读器局部主题显式使用同一份滑块配置，其配色仍来自阅读器自己的 `ColorScheme`。

`widgets/setting_controls.dart` 提供帮助图标、设置标题、重置按钮与设置滑块。滑块以 `null` 表示默认状态，始终显示实际数值；OCR 的默认值在调用处转换为此状态。已在分组内留边距的调用点使用零内边距。桌面阅读器滑块仍保留本地拖动状态和松手提交，只共享主题，不改变保存频率。

## PDF 字符循环

`reader_layout_geometry.dart` 与 `reader_pdf_typesetting.dart` 在模块内复用正则。字符对齐使用的区域扩边矩形在循环前计算一次。空白匹配、UTF-16 偏移、连字处理、公式识别及对齐阈值保持原语义。

验证以 `flutter analyze --no-pub` 和已有模型能力、OCR 设置、用量、服务商预设、PDF 排版回归为主。桌面交互手感与实际帧率仍需运行应用验收。
