# 构建、预览与验收

入口脚本在 [scripts/](../scripts/)，示例的组织方式见[示例说明](../examples/ai_settings/README.md)。

## 跑起来

```bash
bash .claude/skills/flutter-newui-design/scripts/build_demo.sh   # 生成 build/flutter-newui-design/site
bash .claude/skills/flutter-newui-design/scripts/serve_demo.sh   # http://127.0.0.1:8123
```

`build_demo.sh` 在独立 `build/` 工程里跑 l10n、静态分析、Widget 测试和 release Web 构建，不写产品平台目录。改过 `serve_demo.py` 后要重启预览服务，FontManifest 才会用上新映射。

预览服务只读桥接本机已安装字体：sans 用 Segoe UI／微软雅黑，serif 用 Times New Roman／宋体，收藏夹 emoji 用 Segoe UI Emoji。不复制、不打包、不下载字体；emoji 走本机字体是因为 CanvasKit 缺字形时会去 `fonts.gstatic.com` 取字体，离线验收会因此失败。不要用普通 `http.server` 替代，也不要把这个桥接器放到公网。

## 浏览器验收

```bash
uv run --no-project --with playwright --with pillow python -X utf8 \
  .claude/skills/flutter-newui-design/scripts/verify_graphite.py
```

用本机 Chrome，产物在 `build/flutter-newui-design/checks/`（截图 + `graphite-verification.json`）。覆盖四页 × 三视口、字体字节来源、sans／serif、浅深色、长文本、100%／130%／200% 字号、键盘与减少动态效果、分段互斥、单标题、纯图标动作、弹窗与 Esc、收藏夹编辑器与封面、Snackbar、模型获取；并断言无页面异常、无外部运行时请求。改动收藏夹或浮层后，翻一遍同目录截图再下结论。

验收清单里值得单独看的：分段文字中心、重复标题、右侧图标动作、浮层与收藏夹内容自适应。局部静态分析与关键交互测试随构建一起跑。

## 视口与设备

| 设备 | 官方物理宽×高 | PPI | 本预览逻辑视口 | 验证渲染比例 |
|---|---|---|---|---|
| Xiaomi 15 | 1200×2670 px | 460 | 400×890 | 3× |
| iPhone 17 Pro | 1206×2622 px | 460 | 402×874 | 3× |
| 桌面 | 随实际显示器 | 不固定 | 1100×960 | 1× |

[小米规格](https://www.mi.com/global/product/xiaomi-15/specs/)、[Apple 规格](https://www.apple.com/iphone-17-pro/specs/)。物理 PPI 与操作系统布局密度不同，3× 是本预览的明确设定，不声称测得 Xiaomi 系统默认 density。预览按完整矩形视口截图，不模拟系统状态栏、浏览器工具栏与安全区；生产按实际 MediaQuery、安全区、键盘与显示缩放布局，不用硬编码 PPI 推算控件尺寸。

## 边界

这些检查都是本地可丢弃操作，直接跑、修、重跑，不必逐次确认。但它们不等于真机验收：原生系统字体、安全区、生产业务与导航隔离仍要在迁移时单独验。不要把编译成功或示例通过写成真机已通过。
