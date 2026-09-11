import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/animation_constants.dart';
import '../../core/elevation.dart';
import '../../utils/desktop.dart';
import '../../widgets/tactile_press.dart';

/// 桌面下拉菜单宽度下限：内容过窄时（两三个短选项）避免挤成一条。
const double _kMenuMinWidth = 240;

/// 桌面下拉菜单宽度上限。与项目浮层家族对齐：sheet 480 / dialog 540。
const double _kMenuMaxWidth = 480;

/// 桌面下拉菜单高度下限 / 上限。
///
/// 上限 400 ≈ 8 行单行项（`MenuItemButton` 默认高 48 + 面板上下 padding 8），
/// 超出滚动；下限 240 保证极矮窗口仍能显示四行以上。
const double _kMenuMinHeight = 240;
const double _kMenuMaxHeight = 400;

/// 桌面下拉菜单高度上限：窗口高的 60%，clamp 到 [_kMenuMinHeight, _kMenuMaxHeight]。
///
/// 基准是**窗口**而非屏幕——弹出层受窗口约束，菜单不该比窗口还高；
/// `MenuAnchor` 自身还会按可用空间再收窄并自动翻折，这里只负责「菜单感」上限。
double pickerMenuMaxHeight(double windowHeight) =>
    (windowHeight * 0.6).clamp(_kMenuMinHeight, _kMenuMaxHeight);

/// 设置页单选 picker：折叠态一行 + 展开态选项列表，按终端分型。
///
/// - 移动端：bottom sheet 列出全部选项；
/// - 桌面端：锚定下拉菜单（`MenuAnchor`），贴触发框下沿、内容自适应宽、
///   超高滚动，键盘 ↑↓ / Esc 由框架自带。
///
/// 选项数量不参与分型：菜单溢出即滚动，属于正常交互，按数量切会让同一个
/// 控件出现两种模态。
///
/// 决策见 `flutter-design` skill §3.6（替代 SegmentedButton 的阈值）· §3.8（本组件规格）：
/// 选项 ≥ 4，或选项 ≥ 3 且任一标签 ≥ 5 字符时改用本组件——
/// SegmentedButton 等分宽度在此场景会触发 ellipsis 截断或竖向折断。
class SettingPicker<T> extends StatefulWidget {
  final T current;
  final List<T> options;
  final String Function(T) labelFor;
  final String Function(T)? subtitleFor;
  final String sheetTitle;
  final ValueChanged<T> onChanged;

  const SettingPicker({
    super.key,
    required this.current,
    required this.options,
    required this.labelFor,
    this.subtitleFor,
    required this.sheetTitle,
    required this.onChanged,
  });

  @override
  State<SettingPicker<T>> createState() => _SettingPickerState<T>();
}

class _SettingPickerState<T> extends State<SettingPicker<T>> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopOs) return _trigger(context, onTap: () => _showSheet());

    return MenuAnchor(
      style: _menuStyle(context),
      // 与触发框留 4px 间隙，避免菜单与框边缘黏在一起
      alignmentOffset: const Offset(0, 4),
      onOpen: () => setState(() => _menuOpen = true),
      onClose: () => setState(() => _menuOpen = false),
      builder: (_, controller, _) => _trigger(
        context,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [for (final opt in widget.options) _menuItem(context, opt)],
    );
  }

  /// 折叠态触发框：值 + ▼。
  Widget _trigger(BuildContext context, {required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TactilePress(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.labelFor(widget.current),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            AnimatedRotation(
              turns: _menuOpen ? 0.5 : 0,
              duration: kAnimFast,
              curve: kAnimCurve,
              child: Icon(
                Symbols.expand_more_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面下拉菜单外观：与 `app_context_menu` / 首页工具菜单同源参数。
  ///
  /// 宽度下限**不能**写在 `MenuStyle.minimumSize`——面板按 `IntrinsicWidth`
  /// 取子项固有宽，`minimumSize` 被静默忽略（实测 240 不生效）；下限由
  /// 每个选项的 `MenuItemButton.minimumSize` 承担（子项会撑满面板宽）。
  MenuStyle _menuStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
      elevation: const WidgetStatePropertyAll(3),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      maximumSize: WidgetStatePropertyAll(
        Size(
          _kMenuMaxWidth,
          pickerMenuMaxHeight(MediaQuery.sizeOf(context).height),
        ),
      ),
    );
  }

  /// 桌面下拉菜单选项行：单行标签 + 可选副标题，选中项尾随勾选。
  Widget _menuItem(BuildContext context, T opt) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSelected = opt == widget.current;
    final subtitle = widget.subtitleFor?.call(opt);
    return MenuItemButton(
      onPressed: () {
        if (opt != widget.current) widget.onChanged(opt);
      },
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(_kMenuMinWidth, 0),
      ),
      trailingIcon: isSelected
          ? Icon(Symbols.check_rounded, size: 20, color: cs.primary)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.labelFor(opt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? cs.primary : cs.onSurface,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSheet() async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // 桌面端窗口宽时 sheet 居中不撑满全宽，避免 1080p 屏上字横跨整屏。
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.7;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.sheet,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.sheetTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).padding.bottom + 16,
                  ),
                  children: widget.options.map((opt) {
                    final isSelected = opt == widget.current;
                    final subtitle = widget.subtitleFor?.call(opt);
                    return TactilePress(
                      baseColor: Colors.transparent,
                      onTap: () => Navigator.pop(ctx, opt),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.labelFor(opt),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      subtitle,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Symbols.check_rounded,
                              size: 20,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && selected != widget.current) {
      widget.onChanged(selected);
    }
  }
}
