# README 截图

2026-09-15 采集，统一使用浅色主题和不透明 PNG。中英文 README 共用同一组图片，页面切换深色主题时不会透出背景；展示时保持原始比例，不添加机框。

| 图片 | 来源与场景 |
| --- | --- |
| `desktop-library.png` | 用户指定的运行中 Windows 应用，文献库 |
| `desktop-pdf-bilingual.png` | 同一 Windows 应用，同页 PDF 左原文、右译文与图表侧栏 |
| `desktop-reading.png` | 同一 Windows 应用，双语重排阅读、已有标注与图表侧栏 |
| `mobile-pdf.png` | 2203121C，PDF 阅读 |
| `mobile-reading.png` | 2203121C，重排阅读 |
| `mobile-figures.png` | 2203121C，图表浏览 |
| `mobile-ai.png` | 2203121C，全文问答入口 |

手机采集时安装版本为 0.1.3，截图不能作为 0.1.5 移动端验收凭据。手机原图通过 ADB `exec-out screencap -p` 取得，尺寸均为 1440 × 3200。Windows 图片通过目标应用窗口的 `PrintWindow` 客户区截图取得，避免其他窗口遮挡；双排阅读截图临时加宽窗口以触发自适应布局。

截图保留应用实际显示内容。已有翻译缓存用于展示，采集时未发起翻译或 AI 问答请求。更新时请只截阅读界面，避开个人配置、密钥与通知。
