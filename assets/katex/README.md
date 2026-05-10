# KaTeX 离线资源

阅读器的数学公式渲染走 KaTeX，资源被 [ReaderLocalhostServer]
(`lib/services/reader_localhost_server.dart`) 通过 `/_assets/katex/*` 路由从
`rootBundle` 服务，**离线可用、零 CDN 依赖**。

## 安装步骤

### 一键安装（WSL）

在 WSL 中从仓库根目录执行：

```bash
bash scripts/install_katex.sh
```

默认安装 KaTeX `v0.16.11`，并在安装后执行 `flutter pub get`。如需跳过：

```bash
SKIP_FLUTTER_PUB_GET=1 bash scripts/install_katex.sh
```

如需指定版本：

```bash
KATEX_VERSION=0.16.11 bash scripts/install_katex.sh
```

### 手动安装

1. 从 https://github.com/KaTeX/KaTeX/releases/tag/v0.16.11 下载
   **`katex.tar.gz`**（约 800KB）。
2. 解压后把以下文件拷贝到 `assets/katex/` 对应位置（覆盖占位文件）：

```
assets/katex/
├── katex.min.css            ← 必需
├── katex.min.js             ← 必需
├── contrib/
│   └── auto-render.min.js   ← 必需（自动识别 $...$ / $$...$$ 语法）
└── fonts/                   ← 必需（KaTeX CSS 内 @font-face 引用，缺则字符变方框）
    ├── KaTeX_AMS-Regular.woff2
    ├── KaTeX_Caligraphic-Bold.woff2
    ├── ... (约 60 个 woff2 字体文件)
    └── KaTeX_Typewriter-Regular.woff2
```

3. 跑 `flutter pub get` 重建 asset manifest。

## 精简（可选，省 ~600KB 体积）

下载包内可删除：

| 删 | 原因 |
|---|---|
| `*.css.map` / `*.js.map` | source maps，仅 dev 用 |
| 非压缩版 `*.css` / `*.js`（保留 `.min.*`） | 同上 |
| `fonts/*.woff` / `fonts/*.ttf` | 保留 woff2 即可，所有 WebView 都支持 |
| `contrib/` 内除 `auto-render.min.js` 外 | mhchem/copy-tex 等扩展未使用 |

精简后约 ~280KB。

## 验证

放好文件后打开任意带 LaTeX 公式的文献，DevTools Network 面板应看到：

```
GET http://localhost:<PORT>/_assets/katex/katex.min.css         → 200
GET http://localhost:<PORT>/_assets/katex/katex.min.js          → 200
GET http://localhost:<PORT>/_assets/katex/contrib/auto-render.min.js → 200
GET http://localhost:<PORT>/_assets/katex/fonts/KaTeX_Math-Italic.woff2 → 200
```

公式渲染异常通常是 `fonts/` 缺字体——检查 Network 404 即可定位。
