import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

/// NightReader 图片配置：支持 file:// 本地图片和 http(s) 网络图片。
class NRImgConfig extends ImgConfig {
  NRImgConfig({super.errorBuilder})
      : super(
          builder: (url, attrs) {
            Widget image;
            if (url.startsWith('file://') || url.startsWith('/')) {
              final path =
                  url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
              image = Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, error, _) =>
                    errorBuilder?.call(url, attrs['alt'] ?? '', error) ??
                    const _BrokenImage(),
              );
            } else {
              image = Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, error, _) =>
                    errorBuilder?.call(url, attrs['alt'] ?? '', error) ??
                    const _BrokenImage(),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: image,
                ),
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
