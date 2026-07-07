<div align="center">

<img src="../assets/icons/app_icon.png" width="120px" alt="OtterPad"/>

# 獭祭鱼 OtterPad

**AI 驱动的学术文献阅读与管理工具**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/github/license/Cyli00/NightReader)](../LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-brightgreen)]()

[English](../README.md) | 简体中文

</div>

## 这是什么？

OtterPad 是一款学术文献阅读与管理工具，集成 AI 工作流，帮助科研工作者高效阅读、理解和管理文献。

- 📖 沉浸式 PDF 阅读，自定义主题与排版
- 🤖 AI 全文问答，基于提取的完整文本和图表回答问题
- 🌐 文档级段落翻译，保留公式与代码块
- 🔍 多数据源文献搜索与元数据解析
- 📊 图表智能提取与独立浏览

<div align="center">

| 沉浸式阅读 | AI 全文问答 |
|:---:|:---:|
| <img src="./immersive_reading_experience_framed.png" width="280px"/> | <img src="./ask_anything_with_fullcontext_framed.png" width="280px"/> |

</div>

## 功能特性

### 阅读与翻译
- **沉浸式阅读** — 自定义主题配色、字号排版，支持高亮与标注
- **段落级翻译** — 8 并发 worker 逐段翻译，自动保护公式/代码/引用编号
- **图表提取** — 精准识别 PDF 中的 figure/table，支持独立查看和复制

### AI 理解
- **全文问答** — 基于提取的完整文本与图表，AI 回答关于文档的任何问题
- **多模型支持** — OpenAI / Anthropic / Google / 兼容 API，自由切换
- **智能摘要** — AI 生成文献要点总结

### 文献管理
- **多源搜索** — 通过 DOI / PubMed / Crossref / Semantic Scholar 等检索文献
- **AI 重命名** — 基于元数据的智能文件命名
- **分类收藏** — 自定义分类体系与标签
- **Zotero 同步** — 双向同步 Zotero 文献库

### 数据安全
- **云备份** — 支持 S3 / WebDAV 云端备份与恢复
- **自动备份** — 可配置的定时自动备份策略

## 安装

前往 [Releases](https://github.com/Cyli00/NightReader/releases) 下载对应架构的 APK：
- `arm64-v8a` — 大多数现代 Android 设备
- `armeabi-v7a` — 较旧的 32 位设备
- `x86_64` — 模拟器 / ChromeOS

> 桌面端和 iOS 版本正在规划中，尚未发布。

## 技术栈

- **框架** — Flutter 3.x + Dart 3.x
- **状态管理** — Riverpod
- **路由** — GoRouter
- **存储** — Hive (本地) + Flutter Secure Storage (凭据)
- **网络** — Dio + HTTP/2
- **设计语言** — Material Design 3

## 致谢

OtterPad 站在以下优秀开源项目和社区的肩膀上：

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) — 基于 Flutter 的第三方 BiliBili 客户端
- [PDFMathTranslate](https://github.com/PDFMathTranslate/PDFMathTranslate) — AI 驱动的 PDF 翻译，完整保留排版（EMNLP 2025）
- [FlClash](https://github.com/chen08209/FlClash) — 基于 ClashMeta 的多平台代理客户端
- [Kelivo](https://github.com/Chevey339/kelivo) — 基于 Flutter 的多平台 LLM 聊天客户端
- [LINUX DO](https://linux.do/) — 真诚、友善、团结、专业的技术社区，感谢宝贵的反馈与支持

## 开源协议

本项目基于 [GNU General Public License v3.0](../LICENSE) 开源。
