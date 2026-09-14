import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/pdf_thumbnail_service.dart';
import 'package:material_symbols_icons/symbols.dart';

/// PDF 封面组件：从磁盘缓存加载预渲染的 PNG 缩略图。
class PdfCoverRender extends StatefulWidget {
  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  const PdfCoverRender({
    super.key,
    required this.assetPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  State<PdfCoverRender> createState() => _PdfCoverRenderState();
}

class _PdfCoverRenderState extends State<PdfCoverRender> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;
  StreamSubscription<String>? _readySubscription;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant PdfCoverRender oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final request = ++_request;
    final assetPath = widget.assetPath;
    final service = PdfThumbnailService.instance;
    unawaited(_readySubscription?.cancel());
    _readySubscription = service.watchReady(assetPath).listen((path) {
      if (!mounted || request != _request) return;
      setState(() {
        _thumbnailPath = path;
        _isLoading = false;
        _hasError = false;
      });
    });
    setState(() {
      _thumbnailPath = null;
      _isLoading = true;
      _hasError = false;
    });

    try {
      final path = await service.getThumbnailPath(assetPath);

      // 已收到落盘通知后，旧等待的超时/失败不能再覆盖成功状态。
      if (mounted && request == _request && _thumbnailPath == null) {
        setState(() {
          _thumbnailPath = path;
          _isLoading = false;
          _hasError = path == null;
        });
      }
    } catch (e) {
      if (mounted && request == _request && _thumbnailPath == null) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_request;
    unawaited(_readySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_hasError || _thumbnailPath == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Symbols.picture_as_pdf_rounded,
          color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
          size: 48,
        ),
      );
    }

    return Image.file(
      File(_thumbnailPath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.width?.toInt(),
      filterQuality: FilterQuality.medium,
    );
  }
}
