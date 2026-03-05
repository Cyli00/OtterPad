import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/pdf_thumbnail_service.dart';

/// PDF 封面组件：从磁盘缓存加载预渲染的 PNG 缩略图。
class PdfCoverRender extends StatefulWidget {
  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit fit;

  const PdfCoverRender({
    super.key,
    required this.assetPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<PdfCoverRender> createState() => _PdfCoverRenderState();
}

class _PdfCoverRenderState extends State<PdfCoverRender> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

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
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final path = await PdfThumbnailService.instance.getThumbnailPath(
        widget.assetPath,
      );

      if (mounted) {
        setState(() {
          _thumbnailPath = path;
          _isLoading = false;
          _hasError = path == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
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
          Icons.picture_as_pdf,
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
      cacheWidth: widget.width?.toInt(),
      filterQuality: FilterQuality.medium,
    );
  }
}
