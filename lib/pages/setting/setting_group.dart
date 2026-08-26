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
