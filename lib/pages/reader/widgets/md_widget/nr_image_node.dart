import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
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
                      child: Text.rich(
                        TextSpan(
                          children: _parseCaptionSpans(
                            caption,
                            captionStyle ?? const TextStyle(),
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          },
        );
}

/// 解析 caption 中的 LaTeX，返回混合 TextSpan/WidgetSpan 列表。
///
/// API 的 figure_title 常包含不带 $...$ 的裸 LaTeX 命令，
/// 先用 [_wrapBareLatex] 添加定界符，再解析 $...$。
List<InlineSpan> _parseCaptionSpans(String text, TextStyle style) {
  final processed = _wrapBareLatex(text);
  final spans = <InlineSpan>[];
  final regex = RegExp(r'\$([^\$\n]+?)\$');
  var lastEnd = 0;

  for (final match in regex.allMatches(processed)) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(
        text: processed.substring(lastEnd, match.start),
        style: style,
      ));
    }

    final equation = match.group(1)!.trim();
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Math.tex(
        equation,
        textStyle: style,
        mathStyle: MathStyle.text,
        textScaleFactor: 1,
        onErrorFallback: (e) => Text(
          '\$$equation\$',
          style: style.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    ));

    lastEnd = match.end;
  }

  if (lastEnd < processed.length) {
    spans.add(TextSpan(text: processed.substring(lastEnd), style: style));
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: style));
  }

  return spans;
}

// ─── 裸 LaTeX 命令检测与包裹 ───

/// 检测 caption 中以 \command 开头的数学表达式并包裹 $...$。
String _wrapBareLatex(String text) {
  if (!text.contains(r'\')) return text;

  final buf = StringBuffer();
  var i = 0;

  while (i < text.length) {
    if (_isCmd(text, i) || _isSubSupStart(text, i)) {
      final start = i;
      i = _scanMath(text, i);
      // 剥离尾部空格
      var end = i;
      while (end > start && text[end - 1] == ' ') {
        end--;
      }
      buf
        ..write(r'$')
        ..write(text.substring(start, end))
        ..write(r'$')
        ..write(text.substring(end, i));
    } else {
      buf.write(text[i]);
      i++;
    }
  }

  return buf.toString();
}

bool _isCmd(String t, int i) =>
    t[i] == '\\' && i + 1 < t.length && _isAZ(t.codeUnitAt(i + 1));

bool _isAZ(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A;

/// 单字母 + _/^ + {group}/\command/digit/单字母 → 数学起始
bool _isSubSupStart(String t, int i) {
  if (!_isAZ(t.codeUnitAt(i)) || i + 2 >= t.length) return false;
  final next = t.codeUnitAt(i + 1);
  if (next != 0x5F && next != 0x5E) return false; // _ ^
  final after = t.codeUnitAt(i + 2);
  if (after == 0x7B) return true; // {
  if (_isCmd(t, i + 2)) return true; // \cmd
  if (after >= 0x30 && after <= 0x39) return true; // digit
  if (_isAZ(after) && (i + 3 >= t.length || !_isAZ(t.codeUnitAt(i + 3)))) {
    return true; // single letter
  }
  return false;
}

/// 从 \command 起向后扫描连续的数学表达式，返回结束位置。
int _scanMath(String text, int i) {
  final len = text.length;
  var braceDepth = 0;
  var parenDepth = 0;

  while (i < len) {
    final c = text.codeUnitAt(i);

    // \command
    if (_isCmd(text, i)) {
      i += 2;
      while (i < len && _isAZ(text.codeUnitAt(i))) {
        i++;
      }
      continue;
    }
    // { }
    if (c == 0x7B) { braceDepth++; i++; continue; }
    if (c == 0x7D && braceDepth > 0) { braceDepth--; i++; continue; }
    if (braceDepth > 0) { i++; continue; }
    // 数学字符: _ ^ = < > + - . , : ; / 0-9
    if (const {0x5F, 0x5E, 0x3D, 0x3C, 0x3E, 0x2B, 0x2D, 0x2E, 0x2C, 0x3A, 0x3B, 0x2F}
            .contains(c) ||
        (c >= 0x30 && c <= 0x39)) {
      i++;
      continue;
    }
    // ( — 仅当后续内容是数学时才纳入
    if (c == 0x28) {
      var j = i + 1;
      while (j < len && text.codeUnitAt(j) == 0x20) {
        j++;
      }
      if (j < len && _mathAhead(text, j)) { parenDepth++; i++; continue; }
      break;
    }
    // ) — 有配对 ( 时才纳入
    if (c == 0x29 && parenDepth > 0) { parenDepth--; i++; continue; }
    // 空格 — 仅当后续还有数学时才跳过
    if (c == 0x20) {
      var j = i + 1;
      while (j < len && text.codeUnitAt(j) == 0x20) {
        j++;
      }
      if (j < len && _mathAhead(text, j)) { i = j; continue; }
      break;
    }
    // 单字母（变量），多字母（单词）则结束
    if (_isAZ(c)) {
      if (i + 1 < len && _isAZ(text.codeUnitAt(i + 1))) break;
      i++;
      continue;
    }
    break;
  }

  return i;
}

/// 位置 [j] 是否像数学表达式的延续
bool _mathAhead(String t, int j) {
  if (j >= t.length) return false;
  final c = t.codeUnitAt(j);
  if (_isCmd(t, j)) return true;
  if (const {0x5F, 0x5E, 0x7B, 0x3D, 0x3C, 0x3E, 0x2B, 0x2D, 0x2E}
          .contains(c) ||
      (c >= 0x30 && c <= 0x39)) {
    return true;
  }
  if (_isAZ(c) && (j + 1 >= t.length || !_isAZ(t.codeUnitAt(j + 1)))) {
    return true;
  }
  if (c == 0x28 && j + 1 < t.length) return _mathAhead(t, j + 1);
  return false;
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.broken_image_rounded, size: 48);
  }
}
