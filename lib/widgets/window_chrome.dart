import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

class WindowChrome extends StatefulWidget {
  const WindowChrome({super.key});
  static const double height = 36;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> with WindowListener {
  bool _pinned = false;
  bool _maximized = false;
  // 跟随系统窗焦点：失焦时标题栏降饱和（macOS/Windows 原生窗行为）
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isAlwaysOnTop().then((v) {
      windowManager.isMaximized().then((m) {
        if (mounted) {
          setState(() {
            _pinned = v;
            _maximized = m;
          });
        }
      });
    });
    windowManager.isFocused().then((f) {
      if (mounted) setState(() => _focused = f);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: WindowChrome.height,
      child: Stack(
        children: [
          DragToMoveArea(
            child: ColoredBox(
              color: cs.surfaceContainerHighest,
              child: AnimatedOpacity(
                opacity: _focused ? 1.0 : 0.55,
                duration: kAnimFast,
                curve: kAnimCurve,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        'OtterPad',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _Btn(
                      icon: _pinned
                          ? Symbols.keep_rounded
                          : Symbols.keep_off_rounded,
                      fill: _pinned ? 1.0 : 0.0,
                      highlight: _pinned,
                      onTap: () async {
                        final next = !_pinned;
                        await windowManager.setAlwaysOnTop(next);
                        if (mounted) setState(() => _pinned = next);
                      },
                    ),
                    _Btn(
                      icon: Symbols.remove_rounded,
                      onTap: windowManager.minimize,
                    ),
                    _Btn(
                      icon: _maximized
                          ? Symbols.fullscreen_exit_rounded
                          : Symbols.crop_square_rounded,
                      onTap: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                    ),
                    _Btn(
                      icon: Symbols.close_rounded,
                      onTap: windowManager.close,
                      isClose: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withAlpha(80),
            ),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final bool highlight;
  final double fill;

  const _Btn({
    required this.icon,
    required this.onTap,
    this.isClose = false,
    this.highlight = false,
    this.fill = 0,
  });

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _hovered
        ? (widget.isClose
              ? const Color(0xFFE81123)
              : cs.onSurface.withAlpha(24))
        : Colors.transparent;
    final fg = _hovered && widget.isClose
        ? Colors.white
        : (widget.highlight ? cs.primary : cs.onSurface.withAlpha(200));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: kAnimFast,
          width: 40,
          height: WindowChrome.height,
          color: bg,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 20,
            weight: 800,
            fill: widget.fill,
            color: fg,
          ),
        ),
      ),
    );
  }
}
