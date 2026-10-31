---
name: flutter-drive
description: 实机调试 OtterPad 的 UI 与动画：后台 flutter run，常驻守护进程通过 VM Service 在应用内读取界面快照（snap）、点击、拖动、输入、截图（含慢放连拍、区域放大）、读日志、热重载，应用无需前置。需要在真实运行的应用里看界面效果、验证交互或排查运行时报错时使用，不要改用系统截图、computer use、AppleScript 点击等其他手段。
---

# Flutter 实机驱动

`scripts/fd.mjs` 是客户端，命令转发给常驻守护进程 `fdd.mjs`（首次调用自动拉起，脚本改动后自动重启，空闲 30 分钟退出）。守护进程向应用注入 `agent.dart`（热重启后自动重新注入），之后每条命令只是一次本地 RPC。

应用在后台、最小化或被遮挡时照常工作：代理操作期间会强制出帧，界面和动画都会推进。只有需要亲眼看效果时才用 `show` 把窗口前置。

坐标一律是**逻辑像素**，与 `--scale 1` 截图的像素一一对应。会话状态（VM 地址、pid、日志、截图）存在 `.dart_tool/flutter_drive/`。

## 启动

```bash
bash .claude/skills/flutter-drive/scripts/launch.sh [device]   # 默认 macos；会结束上一个会话和残留的应用实例
```

打印 `ready: ws://…` 即可操作。额外的 `flutter run` 参数用 `FLUTTER_RUN_ARGS="--flavor x"` 传入。改完代码执行 `reload`（或 `restart`），不需要重新 launch。

## 先 snap，再按编号操作

```bash
F=.claude/skills/flutter-drive/scripts/fd.mjs
node $F snap            # 可交互元素与标题，每行 @编号 角色 文字 [状态]
node $F tap @3          # 按编号点击
node $F snap 网络       # 只列文字包含「网络」的项
```

`snap` 输出示例：`@5 tap 文献库 / 第 2 个标签，共 2 个 [sel]`。角色有 btn、tap、input（`="当前内容"`）、switch、check、radio、slider、link、scroll、header；状态有 sel、on、off、disabled、focus。`--all` 额外列出纯文本，`--rect` 附带 `(x,y,w,h)`，供区域截图使用。

`@编号` 只对最近一次 snap 有效。执行前会核对该元素是否还在、文字是否一致；页面变化后会返回 `STALE`，此时重新 snap。目标也可以直接写文字（可交互且精确匹配的优先）或 `x y` 坐标。

## 命令

多个命令用 `--` 串联，按顺序执行：`node $F tap 设置 -- wait 500 -- snap`

| 命令 | 作用 |
|---|---|
| `snap [文字] [--all] [--rect]` | 界面快照，见上 |
| `tap <目标>` | 点击；`--hold ms` 调整按住时长 |
| `longpress <目标>` | 长按 700ms |
| `drag <目标> dx dy [--ms 300]` | 从目标拖动一段位移（触摸） |
| `hover <目标>` | 鼠标悬停（桌面 hover 效果） |
| `scroll <目标> dy` | 鼠标滚轮，dy>0 向下 |
| `type <文字> [--submit]` | 写入当前聚焦的输入框并触发 onChanged；先 tap 输入框 |
| `back` | 返回上一页；在根路由上不会退出应用 |
| `shot [名] [--scale s]` | 整屏截图，默认 ×1；只看布局时用 `--scale 0.4` 省 token |
| `shot [名] --rect x,y,w,h` | 区域截图（2x 细节），看圆角、颜色、对齐时用 |
| `burst 名 间隔ms 帧数 [--scale s\|--rect …]` | 连拍，默认 ×0.5 |
| `slow <倍数>` | 设置 `timeDilation` 放慢动画；结束后执行 `slow 1` |
| `wait <ms>` | 等待（期间持续出帧） |
| `show` | 把应用窗口前置（仅 macOS），用户想亲眼看效果时用 |
| `logs [--grep re] [-n N] [--all]` | 只输出上次读取后的新日志（默认最后 80 行） |
| `errors [--all]` | 新日志里的异常、溢出、报错 |
| `reload` / `restart` | 热重载 / 热重启，打印结果或编译错误 |
| `eval <Dart 表达式> [--lib 库uri片段]` | 兜底；默认作用域为 `package:flutter/src/widgets/binding.dart`，该作用域看不到的类型用 `runtimeType.toString()` + `dynamic` 访问 |
| `info` | 窗口逻辑尺寸、dpr、生命周期、是否出帧、timeDilation |
| `stop` | 结束 flutter run 和应用 |

## 调试流程

- **导航**：靠 `snap` 文本定位，不要为了「看现在在哪」而截图。
- **样式**：`snap --rect` 拿到区域，再用 `shot --rect` 只截这一块，不要反复整屏截图。
- **动画**：`slow 8 -- tap … -- burst 名 150 4 --rect … -- slow 1`，看中间帧是否有闪烁或跳变；比对前后两版时用相同的 rect 和间隔。
- **改代码后**：`reload -- errors`，再重复上面的截图命令验证。
- **报错**：先用 `errors` 看摘要，需要上下文再 `logs --grep 关键字`。
- 截图后用 Read 查看 `.dart_tool/flutter_drive/shots/` 下的 png；同名会覆盖，无需清理。

## 注意

- 页面跳转后自动聚焦、异步加载的内容，要先 `wait 500` 左右再操作。
- 截图是 Flutter 图层渲染，不含 macOS 原生标题栏和红绿灯；检查原生窗口外观时如实说明这一点，不要改用系统截图。
- 不要用 `windowManager.hide()` 一类方式关闭或隐藏唯一窗口：macOS 上最后一个窗口关闭后应用会直接退出。
- 测试中改动过的设置（如代理、开关）结束后改回原值。
