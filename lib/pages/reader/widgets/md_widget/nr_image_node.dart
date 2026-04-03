import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

/// figure caption 的 alt text 前缀约定
const _figPrefix = 'fig:';

/// NightReader 图片配置：支持 file:// 本地图片和 http(s) 网络图片。
///
/// 当 alt text 以 `fig:` 开头时，在图片下方渲染 caption 文字。
class NRImgConfig extends ImgConfig {
  NRImgConfig({super.errorBuilder, TextStyle? captionStyle})
      : super(
          builder: (url, attrs) {
            final alt = attrs['alt'] ?? '';
            final isFigure = alt.startsWith(_figPrefix);
            final caption = isFigure ? alt.substring(_figPrefix.length) : '';

            Widget image;
            if (url.startsWith('file://') || url.startsWith('/')) {
              final path =
                  url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
              image = Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, error, _) =>
                    errorBuilder?.call(url, alt, error) ??
                    const _BrokenImage(),
              );
            } else {
              image = Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, error, _) =>
                    errorBuilder?.call(url, alt, error) ??
                    const _BrokenImage(),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: image,
                    ),
                  ),
                  if (isFigure && caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 6,
                        left: 16,
                        right: 16,
                      ),
                      child: Text(
                        caption,
                        style: captionStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          },
        );
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.broken_image_rounded, size: 48);
  }
}
