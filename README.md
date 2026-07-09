<div align="center">

<img src="./assets/icons/app_icon.png" width="120px" alt="OtterPad"/>

# OtterPad

**Mobile Academic Literature Reader & Manager**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/github/license/Cyli00/NightReader)](./LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-brightgreen)]()

English | [简体中文](docs/README_zh.md)

</div>

## Why OtterPad?

Reading PDF papers on a phone is a miserable experience — cramped layout, tiny text, constant zooming and panning. Some reading apps can reflow imported PDFs into HTML for easier reading (WeChat Reading, Apple Books, Kindle), but the reflow often breaks the page structure and drops figures and tables, making things worse instead of better. With what AI can do today, reading academic papers on mobile should be comfortable and interactive.

OtterPad uses PaddleOCR-VL under the hood to power a figure extraction and layout reflow engine that adapts PDF content for small screens while keeping figures, tables, and formulas intact. Full-text translation and AI Q&A round it out, so you can actually get through a paper on your phone.

<div align="center">

| PDF Reader | Immersive Reading |
|:---:|:---:|
| <img src="./docs/PDF_reader_framed.png" width="280px" alt="PDF Reader"/> | <img src="./docs/immersive_reading_experience_framed.png" width="280px" alt="Immersive Reading"/> |

| Figure Extraction | AI Full-Text Q&A |
|:---:|:---:|
| <img src="./docs/extract_figures_for_reading_framed.png" width="280px" alt="Figure Extraction"/> | <img src="./docs/ask_anything_with_fullcontext_framed.png" width="280px" alt="AI Full-Text Q&A"/> |

</div>

## What It Does

### Reading & Reflow

- PDF layout reflow optimized for mobile screens, preserving figures, tables, and formulas
- Customizable themes, font sizing, with highlighting and annotation support

### Figure Extraction

- Automatic figure and table detection and extraction powered by PaddleOCR-VL
- Standalone viewing, copying, and sharing of extracted figures

### Translation & Q&A

- Document-level paragraph translation with automatic protection of formulas, code blocks, and citation markers
- Full-text Q&A grounded in the extracted text and figures, reducing hallucination
- Supports OpenAI, Anthropic, Google, and compatible API providers

### Paper Management

- Multi-source search and metadata resolution via DOI, PubMed, Crossref, Semantic Scholar, etc.
- AI-powered file renaming, custom categories and tags, two-way Zotero sync
- Cloud backup and restore (S3 / WebDAV) with configurable auto-backup

## Installation

Grab the APK for your architecture from [Releases](https://github.com/Cyli00/NightReader/releases):
- `arm64-v8a` — Most modern Android devices
- `armeabi-v7a` — Older 32-bit devices
- `x86_64` — Emulators / ChromeOS

> Desktop and iOS builds are in progress.

## Development

This project was built with the help of [Claude Code](https://claude.com/claude-code), using Flutter 3.x + Dart 3.x.

| Layer | Stack |
| :--- | :--- |
| Framework | Flutter 3.x + Dart 3.x |
| State Management | Riverpod |
| Routing | GoRouter |
| Local Storage | Hive + Flutter Secure Storage (credentials) |
| Networking | Dio + HTTP/2 |
| OCR / Layout Analysis | PaddleOCR-VL |
| Design | Material Design 3 |

## Acknowledgements

These projects and communities provided valuable reference and support:

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) — Third-party BiliBili client built with Flutter
- [PDFMathTranslate](https://github.com/PDFMathTranslate/PDFMathTranslate) — AI-powered PDF translation preserving full layout (EMNLP 2025)
- [FlClash](https://github.com/chen08209/FlClash) — Multi-platform proxy client based on ClashMeta
- [Kelivo](https://github.com/Chevey339/kelivo) — Multi-platform LLM chat client built with Flutter
- [LINUX DO](https://linux.do/) — A sincere, friendly, and professional tech community for invaluable feedback and support

## License

Licensed under [GPL-3.0](./LICENSE).
