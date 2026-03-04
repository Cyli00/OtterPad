import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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
  ui.Image? _renderedImage;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPdfCover();
  }

  Future<void> _loadPdfCover() async {
    PdfDocument? document;
    try {
      // 打开 Asset 中的 PDF
      document = await PdfDocument.openAsset(widget.assetPath);
      if (document.pages.isNotEmpty) {
        // 获取第一页
        final page = document.pages.first;
        // 以稍微大一点的缩放比例渲染以保证清晰度，由于卡片较小，不需要全尺寸全分辨率渲染
        // 根据传入的宽高度或固定值
        final renderWidth = (widget.width ?? 300) * 1.5;
        final renderHeight = (widget.height ?? 400) * 1.5;

        final rendered = await page.render(
          fullWidth: renderWidth,
          fullHeight: renderHeight,
        );

        if (mounted && rendered != null) {
          final image = await rendered.createImage();
          setState(() {
            _renderedImage = image;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } finally {
      // 必须释放文档资源
      document?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_hasError || _renderedImage == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.picture_as_pdf,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(100),
          size: 48,
        ),
      );
    }

    return RawImage(
      image: _renderedImage,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
