import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/api_provider.dart';
import '../../services/agent_model_capability.dart';
import 'agent_add_model_dialog.dart';
import 'agent_model_tester.dart';
import 'agent_role_widgets.dart';

typedef AgentAddModelCallback =
    void Function(String id, {bool setAsDefault, bool setAsFast, bool setAsImage});

/// 打开"管理模型"底部弹窗。
///
/// 这是唯一公开入口——外部调用方无需关心内部 widget 结构。
Future<void> showAgentModelManageSheet({
  required BuildContext context,
  required String baseUrl,
  required String apiKey,
  required AgentApiProvider providerType,
  required String providerLabel,
  required List<String> addedModels,
  required String? currentDefaultModel,
  required String? currentFastModel,
  required String? currentImageModel,
  required AgentAddModelCallback onAdd,
  required ValueChanged<String> onRemove,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ModelManageSheet(
      baseUrl: baseUrl,
      apiKey: apiKey,
      providerType: providerType,
      providerLabel: providerLabel,
      addedModels: addedModels,
      currentDefaultModel: currentDefaultModel,
      currentFastModel: currentFastModel,
      currentImageModel: currentImageModel,
      onAdd: onAdd,
      onRemove: onRemove,
    ),
  );
}

class _ModelManageSheet extends StatefulWidget {
  final String baseUrl;
  final String apiKey;
  final AgentApiProvider providerType;
  final String providerLabel;
  final List<String> addedModels;
  final String? currentDefaultModel;
  final String? currentFastModel;
  final String? currentImageModel;
  final AgentAddModelCallback onAdd;
  final ValueChanged<String> onRemove;

  const _ModelManageSheet({
    required this.baseUrl,
    required this.apiKey,
    required this.providerType,
    required this.providerLabel,
    required this.addedModels,
    required this.currentDefaultModel,
    required this.currentFastModel,
    required this.currentImageModel,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<_ModelManageSheet> createState() => _ModelManageSheetState();
}

class _ModelManageSheetState extends State<_ModelManageSheet> {
  List<String>? _models;
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _imageOnly = false;
  late final Set<String> _localAdded;
  // 跟随用户在本 sheet 内的连续操作更新，避免重复开关时读到过期值
  String? _localDefault;
  String? _localFast;
  String? _localImage;

  @override
  void initState() {
    super.initState();
    _localAdded = Set<String>.from(widget.addedModels);
    _localDefault = widget.currentDefaultModel;
    _localFast = widget.currentFastModel;
    _localImage = widget.currentImageModel;
    _fetchModels();
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await fetchAvailableModels(
        provider: widget.providerType,
        baseUrl: widget.baseUrl,
        apiKey: widget.apiKey,
      );
      if (mounted) setState(() => _models = list);
    } catch (_) {
      if (mounted) setState(() => _error = '获取模型列表失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _filtered {
    if (_models == null) return [];
    var result = _models!;
    if (_imageOnly) {
      result = result
          .where(
            (m) => AgentModelCapability.isImageGenerationModel(
              provider: widget.providerType,
              modelId: m,
            ),
          )
          .toList();
    }
    if (_query.isEmpty) return result;
    final q = _query.toLowerCase();
    return result.where((m) => m.toLowerCase().contains(q)).toList();
  }

  bool _isAdded(String id) => _localAdded.contains(id);

  Future<void> _showAddConfirm(String id) async {
    final isImageModel = AgentModelCapability.isImageGenerationModel(
      provider: widget.providerType,
      modelId: id,
    );

    if (isImageModel) {
      widget.onAdd(id, setAsImage: true);
      setState(() {
        _localAdded.add(id);
        _localImage = id;
      });
      return;
    }

    final choice = await showAgentAddModelDialog(
      context: context,
      modelId: id,
      currentDefault: _localDefault,
      currentFast: _localFast,
      currentImage: _localImage,
    );
    if (choice == null) return;

    widget.onAdd(
      id,
      setAsDefault: choice.setAsDefault,
      setAsFast: choice.setAsFast,
      setAsImage: choice.setAsImage,
    );
    setState(() {
      _localAdded.add(id);
      if (choice.setAsDefault) _localDefault = id;
      if (choice.setAsFast) _localFast = id;
      if (choice.setAsImage) _localImage = id;
    });
  }

  void _handleRemove(String id) {
    widget.onRemove(id);
    setState(() {
      _localAdded.remove(id);
      if (_localDefault == id) _localDefault = null;
      if (_localFast == id) _localFast = null;
      if (_localImage == id) _localImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    final filtered = _filtered;
    final addedCount = _localAdded.length;
    // 主题色在色盘上的互补色（hue + 180°），保留 primaryContainer 的明度/饱和度特征
    final containerHsl = HSLColor.fromColor(cs.primaryContainer);
    final onContainerHsl = HSLColor.fromColor(cs.onPrimaryContainer);
    final compContainer = containerHsl
        .withHue((containerHsl.hue + 180) % 360)
        .toColor();
    final onCompContainer = onContainerHsl
        .withHue((onContainerHsl.hue + 180) % 360)
        .toColor();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
            _buildHeader(theme, cs, addedCount, compContainer, onCompContainer),
            const SizedBox(height: 12),
            _buildSearchField(theme, cs),
            const SizedBox(height: 8),
            Flexible(child: _buildListArea(theme, cs, filtered)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme cs,
    int addedCount,
    Color compContainer,
    Color onCompContainer,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
      child: Row(
        children: [
          Text(
            '${widget.providerLabel} 模型',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          if (_models != null) ...[
            const SizedBox(width: 10),
            _CountPill(
              value: _models!.length,
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
            ),
            if (addedCount > 0) ...[
              const SizedBox(width: 6),
              _CountPill(
                value: addedCount,
                bg: compContainer,
                fg: onCompContainer,
              ),
            ],
          ],
          const Spacer(),
          IconButton(
            icon: Icon(
              Symbols.refresh_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: '刷新',
            onPressed: _fetchModels,
          ),
          IconButton(
            icon: Icon(
              _imageOnly ? Symbols.image_rounded : Symbols.image_search_rounded,
              size: 20,
              color: _imageOnly ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _imageOnly ? '显示全部模型' : '仅显示生图模型',
            onPressed: () => setState(() => _imageOnly = !_imageOnly),
          ),
          IconButton(
            icon: Icon(
              Symbols.close_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: '搜索模型 ID 或名称',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
          prefixIcon: Icon(
            Symbols.search_rounded,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          filled: true,
          fillColor: cs.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildListArea(
    ThemeData theme,
    ColorScheme cs,
    List<String> filtered,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.cloud_off_rounded,
              size: 40,
              color: cs.error.withAlpha(160),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _fetchModels,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          _imageOnly ? '未检测到支持图片输出的模型' : '无匹配结果',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) =>
          _buildCandidateRow(theme, cs, filtered[index]),
    );
  }

  Widget _buildCandidateRow(ThemeData theme, ColorScheme cs, String id) {
    final added = _isAdded(id);
    final isDefault = _localDefault == id;
    final isFast = _localFast == id;
    final isImageModel = AgentModelCapability.isImageGenerationModel(
      provider: widget.providerType,
      modelId: id,
    );

    return Material(
      color: added ? cs.primaryContainer.withAlpha(60) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                id,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: added ? FontWeight.w600 : FontWeight.w400,
                  color: added ? cs.primary : cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDefault) ...[
              const SizedBox(width: 6),
              RoleBadge(
                label: '专家',
                bg: cs.primaryContainer,
                fg: cs.onPrimaryContainer,
              ),
            ],
            if (isFast) ...[
              const SizedBox(width: 4),
              RoleBadge(
                label: '快速',
                bg: cs.tertiaryContainer,
                fg: cs.onTertiaryContainer,
              ),
            ],
            if (isImageModel) ...[
              const SizedBox(width: 4),
              RoleBadge(
                label: '生图',
                bg: cs.secondaryContainer,
                fg: cs.onSecondaryContainer,
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: Icon(
                  added ? Symbols.remove_rounded : Symbols.add_rounded,
                  size: 22,
                  color: added ? cs.primary : cs.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                tooltip: added ? '移除' : '添加',
                onPressed: () {
                  if (added) {
                    _handleRemove(id);
                  } else {
                    _showAddConfirm(id);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// header 右侧的小计数胶囊
class _CountPill extends StatelessWidget {
  final int value;
  final Color bg;
  final Color fg;
  const _CountPill({required this.value, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      constraints: const BoxConstraints(minWidth: 28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
