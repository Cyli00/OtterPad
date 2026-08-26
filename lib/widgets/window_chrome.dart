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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isAlwaysOnTop().then((v) {
      windowManager.isMaximized().then((m) {
        if (mounted) setState(() { _pinned = v; _maximized = m; });
      });
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: WindowChrome.height,
      child: DragToMoveArea(
        child: Container(
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              const Spacer(),
              _Btn(
                icon: _pinned ? Symbols.keep_rounded : Symbols.keep_off_rounded,
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
        ? (widget.isClose ? const Color(0xFFE81123) : cs.onSurface.withAlpha(24))
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
          child: Icon(widget.icon, size: 20, weight: 800, fill: widget.fill, color: fg),
        ),
      ),
    );
  }
}
