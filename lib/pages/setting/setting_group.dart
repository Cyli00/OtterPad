import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 设置分组容器：primary 色标题 + 24 圆角 `surfaceContainerHigh` 容器。
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
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
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

/// 设置页输入框统一样式：与 [SettingPicker] 折叠态同款白底、浅描边、16 圆角。
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
  OutlineInputBorder outline(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: side,
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant.withAlpha(120),
    ),
    helperText: helperText,
    helperStyle: theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: cs.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: outline(BorderSide.none),
    enabledBorder: outline(BorderSide(color: cs.outlineVariant.withAlpha(100))),
    disabledBorder: outline(
      BorderSide(color: cs.outlineVariant.withAlpha(50)),
    ),
    focusedBorder: outline(BorderSide(color: cs.primary, width: 2)),
  );
}
