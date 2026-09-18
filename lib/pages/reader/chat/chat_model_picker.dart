import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/elevation.dart';
import '../../../core/l10n.dart';
import '../../../providers/agent_api_provider.dart';
import '../../../services/document_chat_service.dart';
import '../../../services/model_capability_store.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/ai_brand_icon.dart';
import '../../../widgets/tactile_press.dart';
import '../../setting/agent_role_widgets.dart';
import '../../setting/setting_picker.dart';

/// 桌面下拉菜单宽度：与 `flutter-design` §3.8 同一区间。
///
/// 选项行内容自适应会把面板压到最长模型 ID 的宽度，而本面板顶部还带搜索框，
/// 需要稳定宽度；因此按窗口宽派生并 clamp 到同一区间。
const double _kMenuMinWidth = 240;
const double _kMenuMaxWidth = 480;

/// 会话输入框的模型选择器：折叠态一枚 chip，展开态按终端分型，
/// 与 `SettingPicker` 同一套规则——移动端 bottom sheet，桌面端锚定下拉菜单。
///
/// 视觉对齐 `flutter-design`：§3.2 sheet 容器（`surfaceContainerHigh` + 28 圆角
/// + grabber）· §3.4 搜索框 · §3.8 选项行（透明底色，选中 = primary 文字 + 勾）。
/// 图标统一走 [AiBrandIcon] 的固定外框，折叠态与列表内同尺寸。
class ChatModelPicker extends ConsumerWidget {
  final bool requireImageInput;
  final ChatModelSelection? selected;
  final ValueChanged<ChatModelSelection> onChanged;
  const ChatModelPicker({
    super.key,
    this.selected,
    required this.onChanged,
    this.requireImageInput = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentApiProvider);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final current =
        selected ??
        (!requireImageInput &&
                state.defaultRole.id != null &&
                state.defaultRole.modelId != null
            ? (id: state.defaultRole.id!, modelId: state.defaultRole.modelId!)
            : null);

    /// 折叠态 chip：高度对齐同行 36×36 工具按钮（图标框 32 + 上下各 2）。
    Widget button(VoidCallback onTap) => Tooltip(
      message: current == null
          ? ''
          : '${l10n.chatSelectModel}: ${current.modelId}',
      child: TactilePress(
        baseColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 8, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiBrandIcon(
                name: current?.modelId ?? '',
                fallback: state.byId(current?.id)?.name ?? '',
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  current?.modelId ?? l10n.chatSelectModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Symbols.expand_more_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    final size = MediaQuery.sizeOf(context);
    if (isDesktopOs) {
      final controller = MenuController();
      return MenuAnchor(
        controller: controller,
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          maximumSize: WidgetStatePropertyAll(
            Size(_kMenuMaxWidth, pickerMenuMaxHeight(size.height)),
          ),
        ),
        builder: (_, controller, _) => button(
          () => controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          SizedBox(
            width: (size.width - 48).clamp(_kMenuMinWidth, _kMenuMaxWidth),
            height: pickerMenuMaxHeight(size.height),
            child: _ModelOptions(
              requireImageInput: requireImageInput,
              selected: current,
              onChanged: (option) {
                controller.close();
                onChanged(option);
              },
            ),
          ),
        ],
      );
    }
    return button(
      () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 480),
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              constraints: BoxConstraints(maxHeight: size.height * .7),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: AppShadows.sheet,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withAlpha(80),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Flexible(
                    child: _ModelOptions(
                      requireImageInput: requireImageInput,
                      selected: current,
                      onChanged: (option) {
                        Navigator.of(sheetContext).pop();
                        onChanged(option);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelOptions extends ConsumerStatefulWidget {
  final bool requireImageInput;
  final ChatModelSelection? selected;
  final ValueChanged<ChatModelSelection> onChanged;
  const _ModelOptions({
    required this.selected,
    required this.onChanged,
    this.requireImageInput = false,
  });

  @override
  ConsumerState<_ModelOptions> createState() => _ModelOptionsState();
}

class _ModelOptionsState extends ConsumerState<_ModelOptions> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentApiProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;
    final l10n = context.l10n;

    final rows = <Widget>[];
    for (final instance in state.instances) {
      final models = instance.models
          .where(
            (model) =>
                instance.capabilityFor(model).textOutput &&
                (!widget.requireImageInput ||
                    instance.capabilityFor(model).imageInput) &&
                !instance.capabilityFor(model).embedding &&
                '$model ${instance.name}'.toLowerCase().contains(_query),
          )
          .toList();
      if (models.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 2),
          child: Row(
            children: [
              AiBrandIcon(name: instance.name, fallback: instance.baseUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  instance.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${models.length}',
                style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
      for (final model in models) {
        final option = (id: instance.id, modelId: model);
        final isSelected = widget.selected == option;
        final roles = <RoleBadge>[
          if (instance.id == state.defaultRole.id &&
              model == state.defaultRole.modelId)
            RoleBadge(
              label: l10n.expert,
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
            ),
          if (instance.id == state.fastRole.id &&
              model == state.fastRole.modelId)
            RoleBadge(
              label: l10n.fast,
              bg: cs.secondaryContainer,
              fg: cs.onSecondaryContainer,
            ),
        ];
        rows.add(
          TactilePress(
            baseColor: Colors.transparent,
            onTap: () => widget.onChanged(option),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Semantics(
              selected: isSelected,
              button: true,
              child: Row(
                children: [
                  AiBrandIcon(name: model, fallback: instance.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? cs.primary : cs.onSurface,
                          ),
                        ),
                        if (roles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: roles,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(Symbols.check_rounded, size: 20, color: cs.primary),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text(
            l10n.chatSelectModel,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            style: text.bodyMedium,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: l10n.searchModelHint,
              hintStyle: text.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant.withAlpha(120),
              ),
              prefixIcon: Icon(
                Symbols.search_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withAlpha(100)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        Flexible(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Text(
                    l10n.chatNoModels,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView(
                  primary: false,
                  padding: EdgeInsets.fromLTRB(
                    8,
                    8,
                    8,
                    MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  children: rows,
                ),
        ),
      ],
    );
  }
}
