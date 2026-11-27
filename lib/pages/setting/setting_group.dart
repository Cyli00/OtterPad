import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

/// 设置分组容器（Folio）：眉题（小号、加宽字距、中性色）+ 纸色底、
/// 1px 细线、10 圆角的容器。不再用 primary 色加粗标题和灰色色块。
///
/// 收敛自原各设置页七份逐像素相同的 `_buildGroup` 拷贝。
/// 内置 `Material(transparency)` 祖先：内部 ListTile/RadioListTile 的
/// 选中色与 ink 若没有最近的 Material 祖先，会被 DecoratedBox 背景盖住
/// （框架断言报错）——network 页曾独带此修复，现统一内置。
class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.x1,
            bottom: AppSpace.x3,
            top: AppSpace.x8,
          ),
          child: Text(eyebrowText(title), style: AppType.eyebrow(context)),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppStroke.rule(cs)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ],
    );
  }
}

/// 设置页卡片内容的最大宽度。
const double kSettingContentMaxWidth = 728;

/// 设置页滚动列表：宽屏时用左右内边距把内容限宽居中，滚动区域仍铺满
/// 整栏，两侧空白处也能用滚轮 / 触控板滚动。窄屏时左右各 16。
class SettingListView extends StatelessWidget {
  const SettingListView({super.key, required this.children});

  final List<Widget> children;

  /// 内容左缘到所在栏左缘的距离；宽屏详情标题据此与卡片对齐。
  static double sidePadding(double width) =>
      math.max(16, (width - kSettingContentMaxWidth) / 2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = sidePadding(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 8, side, 40),
          children: children,
        );
      },
    );
  }
}

/// 设置页输入框统一样式：比分组纸面略深的底、1px 细线、6 圆角，聚焦时
/// 1.5px 强调色。
/// 页面里字段名放在输入框上方；[labelText] 只用于弹窗表单、并排的短字段等
/// 放不下上方标签的场景。
InputDecoration settingFieldDecoration(
  BuildContext context, {
  String? hint,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? helperText,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: AppRadius.smAll, borderSide: side);
  return InputDecoration(
    labelText: labelText,
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant.withAlpha(150),
    ),
    helperText: helperText,
    helperStyle: theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: cs.surface,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpace.x3,
      vertical: AppSpace.x3,
    ),
    border: outline(AppStroke.side(cs)),
    enabledBorder: outline(AppStroke.side(cs)),
    disabledBorder: outline(
      BorderSide(color: cs.outlineVariant.withAlpha(110)),
    ),
    focusedBorder: outline(
      BorderSide(color: cs.primary, width: AppStroke.emphasis),
    ),
  );
}
