import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/elevation.dart';
import '../../core/l10n.dart';
import '../../providers/api_provider.dart';
import '../../services/agent_model_capability.dart';
import '../../services/model_capability_store.dart';
import '../../services/haptics.dart';
import '../../utils/desktop.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tactile_press.dart';
import 'agent_add_model_dialog.dart';
import 'agent_model_tester.dart';
import 'agent_role_widgets.dart';

typedef AgentAddModelCallback =
    void Function(
      String id, {
      bool setAsDefault,
      bool setAsFast,
      bool setAsImage,
    });

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
  final content = _ModelManageSheet(
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
    asDialog: isDesktopOs,
  );
  if (isDesktopOs) {
    return showAppDialog<void>(context: context, builder: (_) => content);
  }
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => content,
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
  final bool asDialog;

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
    this.asDialog = false,
  });

  @override
  State<_ModelManageSheet> createState() => _ModelManageSheetState();
}

class _ModelManageSheetState extends State<_ModelManageSheet> {
  List<String>? _models;
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _imageGenOnly = false;
  bool _multimodalOnly = false;
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
    } on DioException catch (e) {
      // 透出真实失败原因（401 / 404 无该端点 / 网络错误），便于区分排查
      if (mounted) {
        setState(
          () => _error =
              '${context.l10n.fetchModelsFailed}\n${describeDioError(e)}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.fetchModelsFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 能力判定走远程表优先（modelcaps geosite 订阅），未命中回退正则推断。
  AgentModelCapability _capOf(String id) =>
      ModelCapabilityStore.instance.lookup(id) ??
      AgentModelCapability.infer(provider: widget.providerType, modelId: id);

  List<String> get _filtered {
    if (_models == null) return [];
    var result = _models!;
    if (_imageGenOnly) {
      result = result
          .where((m) => ModelCapabilityStore.instance.isImageGenerationModel(m))
          .toList();
    }
    if (_multimodalOnly) {
      result = result.where((m) => _capOf(m).imageInput).toList();
    }
    if (_query.isEmpty) return result;
    final q = _query.toLowerCase();
    return result.where((m) => m.toLowerCase().contains(q)).toList();
  }

  bool _isAdded(String id) => _localAdded.contains(id);

  Future<void> _showAddConfirm(String id) async {
    final isImageModel = ModelCapabilityStore.instance.isImageGenerationModel(
      id,
    );

    if (isImageModel) {
      widget.onAdd(id, setAsImage: true);
      setState(() {
        _localAdded.add(id);
        _localImage = id;
      });
      return;
    }

    final cap = _capOf(id);
    final choice = await showAgentAddModelDialog(
      context: context,
      modelId: id,
      currentDefault: _localDefault,
      currentFast: _localFast,
      isMultimodal: cap.imageInput,
    );
    if (choice == null) return;

    widget.onAdd(
      id,
      setAsDefault: choice.setAsDefault,
      setAsFast: choice.setAsFast,
    );
    setState(() {
      _localAdded.add(id);
      if (choice.setAsDefault) _localDefault = id;
      if (choice.setAsFast) _localFast = id;
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

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.asDialog)
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
          )
        else
          const SizedBox(height: 8),
        _buildHeader(theme, cs, addedCount, compContainer, onCompContainer),
        const SizedBox(height: 12),
        _buildSearchField(theme, cs),
        const SizedBox(height: 8),
        Flexible(child: _buildListArea(theme, cs, filtered)),
      ],
    );

    if (widget.asDialog) {
      final lo = 320.0;
      final computed = MediaQuery.sizeOf(context).width * 0.85;
      final hi = math.max(lo, math.min(540.0, computed));
      final width = computed.clamp(lo, hi);
      return Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: width, height: maxH, child: column),
      );
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.sheet,
        ),
        child: column,
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
      // Row 在窄屏（≤ ~330px）会 overflow：标题 + 2 个 pill + 3 个 IconButton
      // 自然宽度 ~354px。Expanded 把"标题 + pill"作为一组挤压区独占剩余空间；
      // Text 用 Flexible + ellipsis 让标题在极窄屏时优先被截断（pill 信息更紧凑、
      // 更值得完整保留）。
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    context.l10n.providerModels(widget.providerLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
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
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _multimodalOnly
                  ? Symbols.visibility_rounded
                  : Symbols.visibility_off_rounded,
              size: 20,
              color: _multimodalOnly ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _multimodalOnly
                ? context.l10n.showAllModels
                : context.l10n.showMultimodalModels,
            onPressed: () {
              Haptics.soft();
              setState(() {
                _multimodalOnly = !_multimodalOnly;
                if (_multimodalOnly) _imageGenOnly = false;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Symbols.palette_rounded,
              size: 20,
              color: _imageGenOnly ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _imageGenOnly
                ? context.l10n.showAllModels
                : context.l10n.showImageGenModels,
            onPressed: () {
              Haptics.soft();
              setState(() {
                _imageGenOnly = !_imageGenOnly;
                if (_imageGenOnly) _multimodalOnly = false;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Symbols.close_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: context.l10n.close,
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context);
            },
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
          hintText: context.l10n.searchModelHint,
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

  double get _listBottomPad =>
      (widget.asDialog ? 16.0 : MediaQuery.of(context).padding.bottom) + 16;

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

    // 手动添加行：搜索框输入的 id 不在拉取列表中且未添加时出现。
    // 兜底 Zhipu / Doubao 等无 /models 列表端点的服务商，以及自建反代。
    final manualId = _query.trim();
    final showManual =
        manualId.isNotEmpty &&
        !_isAdded(manualId) &&
        !(_models?.contains(manualId) ?? false);

    if (_error != null) {
      return ListView(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 4,
          bottom: _listBottomPad,
        ),
        children: [
          if (showManual) _buildManualAddRow(theme, cs, manualId),
          Padding(
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
                  onPressed: () {
                    Haptics.soft();
                    _fetchModels();
                  },
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (filtered.isEmpty && !showManual) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          _imageGenOnly
              ? context.l10n.noImageGenModels
              : _multimodalOnly
              ? context.l10n.noMultimodalModels
              : context.l10n.noResults,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    final manualOffset = showManual ? 1 : 0;
    return ListView.separated(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 4,
        bottom: _listBottomPad,
      ),
      itemCount: filtered.length + manualOffset,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (showManual && index == 0) {
          return _buildManualAddRow(theme, cs, manualId);
        }
        return _buildCandidateRow(theme, cs, filtered[index - manualOffset]);
      },
    );
  }

  /// 手动添加搜索框中输入的模型 id
  Widget _buildManualAddRow(ThemeData theme, ColorScheme cs, String id) {
    return TactilePress(
      onTap: () => _showAddConfirm(id),
      baseColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Symbols.add_circle_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.addModelById(id),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(ThemeData theme, ColorScheme cs, String id) {
    final added = _isAdded(id);
    final isDefault = _localDefault == id;
    final isFast = _localFast == id;
    final cap = _capOf(id);

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
            if (cap.imageInput) ...[
              const SizedBox(width: 4),
              _CapDot(
                icon: Symbols.visibility_rounded,
                tooltip: context.l10n.image,
              ),
            ],
            if (cap.imageOutput) ...[
              const SizedBox(width: 4),
              _CapDot(
                icon: Symbols.palette_rounded,
                tooltip: context.l10n.imageGen,
                color: cs.secondaryContainer,
                iconColor: cs.onSecondaryContainer,
              ),
            ],
            if (cap.tool) ...[
              const SizedBox(width: 4),
              _CapDot(
                icon: Symbols.gavel_rounded,
                tooltip: context.l10n.roleBadgeTools,
              ),
            ],
            if (cap.reasoning) ...[
              const SizedBox(width: 4),
              _CapDot(
                icon: Symbols.neurology_rounded,
                tooltip: context.l10n.reasoning,
              ),
            ],
            if (isDefault) ...[
              const SizedBox(width: 6),
              RoleBadge(
                label: context.l10n.expert,
                bg: cs.primaryContainer,
                fg: cs.onPrimaryContainer,
              ),
            ],
            if (isFast) ...[
              const SizedBox(width: 4),
              RoleBadge(
                label: context.l10n.fast,
                bg: cs.tertiaryContainer,
                fg: cs.onTertiaryContainer,
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
                tooltip: added
                    ? context.l10n.removeModel
                    : context.l10n.addModel,
                onPressed: () {
                  Haptics.soft();
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

/// 模型能力角标：22px 圆形图标盒（视觉 / 工具 / 推理）
class _CapDot extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final Color? iconColor;
  const _CapDot({
    required this.icon,
    required this.tooltip,
    this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 14,
          fill: 1,
          color: iconColor ?? cs.onSurfaceVariant,
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
