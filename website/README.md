# OtterPad 介绍站

首页与使用指南参考 Zed 的紧凑导航、细边框和文档布局，沿用 OtterPad 的纸白、石墨黑与鼠尾草绿。静态 HTML，无运行时框架、外部字体或 CDN 依赖。

## 维护与预览

在仓库根目录执行：

```bash
node website/build.mjs
uv run --no-project python -m http.server 4173 --bind 127.0.0.1 --directory website
```

打开 `http://127.0.0.1:4173/`，英文版在 `en/`，使用指南在 `docs/` 和 `en/docs/`。

- `src/`：页面模板与共用页头、页脚；修改这些文件，不直接修改生成的 HTML。
- `style.css`：配色 Token、页面布局与响应式样式。
- `site.js`：截图标签切换、移动导航、语言跳转与文档章节定位。
- `../lib/l10n/app_{zh,en}.arb` 中的 `website*`：网站文案。改后执行 `flutter gen-l10n`，再运行网站构建。
- `assets/*.webp`：由 `docs/screenshots/` 中的同名截图生成主题预览，清除手机外框阴影，界面底色与蓝色强调色映射到网站配色。论文原页、封面、图表与标注工具的语义色保留；原始 PNG 不修改。水獭标识沿用原有素材。

截图更新后运行 `uv run website/prepare_images.py`。脚本使用 Pillow 与 NumPy，从 `style.css` 读取配色；图表保护区域对应当前素材坐标，替换截图时需核对。输出使用无损 WebP，校验保护区域像素与原图一致。

生成的四个 HTML 页面随源码保存，可直接部署 `website/` 目录，也支持挂载在子路径下。无需部署 Flutter 的 `web/` 目录。下载链接统一前往 `Cyli00/OtterPad` 的 Releases，让用户选择对应架构的安装包。
