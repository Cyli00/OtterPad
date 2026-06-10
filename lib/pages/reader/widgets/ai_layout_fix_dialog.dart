import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../providers/api_provider.dart';
import '../../../services/ai_layout_fix_service.dart';
import '../../../services/haptics.dart';

enum _State { analyzing, confirm, progress, complete, error }

class AiLayoutFixDialog extends StatefulWidget {
  final String documentId;
  final AgentApiState agentState;
  final VoidCallback onComplete;

  const AiLayoutFixDialog({
    super.key,
    required this.documentId,
    required this.agentState,
    required this.onComplete,
  });

  @override
  State<AiLayoutFixDialog> createState() => _AiLayoutFixDialogState();
}

class _AiLayoutFixDialogState extends State<AiLayoutFixDialog> {
  _State _state = _State.analyzing;
  AiLayoutFixAnalysis? _analysis;
  String _statusKey = '';
  int _batchCurrent = 0;
  int _batchTotal = 0;
  AiLayoutFixSummary? _summary;
  String? _error;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _analyze() async {
    try {
      final analysis = await AiLayoutFixService.analyze(
        documentId: widget.documentId,
      );
      if (!mounted) return;
      if (analysis.isEmpty) {
        setState(() {
          _state = _State.error;
          _error = context.l10n.aiLayoutFixNoContent;
        });
        return;
      }
      setState(() {
        _analysis = analysis;
        _state = _State.confirm;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _error = e.toString();
      });
    }
  }

  Future<void> _execute() async {
    final analysis = _analysis!;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    setState(() => _state = _State.progress);

    void onProgress(String stage, int current, int total) {
      if (!mounted) return;
      setState(() {
        _statusKey = stage;
        _batchCurrent = current;
        _batchTotal = total;
      });
    }

    try {
      final result = await AiLayoutFixService.execute(
        analysis: analysis,
        agentState: widget.agentState,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );

      if (cancelToken.isCancelled) return;

      final summary = await AiLayoutFixService.applyResults(
        analysis: analysis,
        result: result,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _state = _State.complete;
      });
      widget.onComplete();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _error = e.message ?? e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _error = e.toString();
      });
    }
  }

  String _localizedStatus(BuildContext context) {
    final l10n = context.l10n;
    final base = switch (_statusKey) {
      'rendering' => l10n.aiLayoutFixRendering,
      'calling' => l10n.aiLayoutFixCalling,
      'applying' => l10n.aiLayoutFixApplying,
      'cropping' => l10n.aiLayoutFixCropping,
      _ => l10n.aiLayoutFixAnalyzing,
    };
    final isBatchStage = _statusKey == 'rendering' || _statusKey == 'calling';
    if (isBatchStage && _batchTotal > 1) {
      return '$base ($_batchCurrent/$_batchTotal)';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AnimatedSize(
          duration: kAnim,
          curve: kAnimCurve,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Symbols.automation_rounded,
                      size: 24,
                      fill: 1,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.aiLayoutFix,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildContent(cs, l10n, theme),
                const SizedBox(height: 20),
                _buildActions(cs, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, dynamic l10n, ThemeData theme) {
    switch (_state) {
      case _State.analyzing:
        return Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.aiLayoutFixAnalyzing,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        );

      case _State.confirm:
        final tokens = _analysis!.estimatedTokens;
        final tokenStr = tokens > 1000
            ? '${(tokens / 1000).toStringAsFixed(1)}k'
            : tokens.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiLayoutFixConfirmMessage(tokenStr),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _infoChip(
              cs,
              theme,
              Symbols.image_rounded,
              '${_analysis!.targetPages.length} pages',
            ),
            const SizedBox(height: 4),
            _infoChip(
              cs,
              theme,
              Symbols.function_rounded,
              '${_analysis!.formulaParagraphs.length} paragraphs',
            ),
          ],
        );

      case _State.progress:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizedStatus(context),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // 多批次时按已完成批次显示确定进度，单批次保持不确定动画
                value: _batchTotal > 1
                    ? (_batchCurrent - 1).clamp(0, _batchTotal) / _batchTotal
                    : null,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        );

      case _State.complete:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.check_circle_rounded,
                    size: 20, fill: 1, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.aiLayoutFixComplete,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (_summary != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.aiLayoutFixSummary(
                  _summary!.paragraphsFixed,
                  _summary!.figuresAdjusted,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.aiLayoutFixRevertHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        );

      case _State.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.error_rounded, size: 20, fill: 1, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
    }
  }

  Widget _infoChip(
    ColorScheme cs,
    ThemeData theme,
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, fill: 1, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(ColorScheme cs, dynamic l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: switch (_state) {
        _State.analyzing => [
            TextButton(
              onPressed: () {
                Haptics.soft();
                Navigator.pop(context);
              },
              child: Text(l10n.cancel),
            ),
          ],
        _State.confirm => [
            TextButton(
              onPressed: () {
                Haptics.soft();
                Navigator.pop(context);
              },
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                Haptics.soft();
                _execute();
              },
              child: Text(l10n.confirm),
            ),
          ],
        _State.progress => [
            TextButton(
              onPressed: () {
                Haptics.soft();
                _cancelToken?.cancel();
              },
              child: Text(l10n.cancel),
            ),
          ],
        _State.complete || _State.error => [
            TextButton(
              onPressed: () {
                Haptics.soft();
                Navigator.pop(context);
              },
              child: Text(l10n.confirm),
            ),
          ],
      },
    );
  }
}
