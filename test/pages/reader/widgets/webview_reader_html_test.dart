import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/widgets/reader_background.dart';
import 'package:otter_pad/pages/reader/widgets/webview_reader_html.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';

void main() {
  const palette = ReaderPalette(
    background: Colors.white,
    text: Colors.black,
    secondaryText: Colors.black54,
    link: Colors.blue,
    divider: Colors.black12,
    codeBlock: Color(0xFFF5F5F5),
  );

  test('显示公式结束符后接正文时继续解析后续 Markdown', () {
    final html = buildReaderHtml(
      markdownContent: r'''
## Feature selection

The importance score is calculated as follows:

$$
I(X_{i})=\frac{1}{T}\sum_{t=1}^{T}\widehat{I}_{t}(X_{i})
$$ where X represents the gene expression value.

## References

1. Example reference.

## Figure legends

Figure 1. Example caption.
''',
      palette: palette,
      settings: const ReaderSettingsState(),
      baseHref: '/library/doc/',
    );

    expect(html, contains('<div class="math-display">'));
    expect(html, contains('<p>where X represents'));
    expect(html, contains('<h2 id="references">References</h2>'));
    expect(html, contains('<h2 id="figure-legends">Figure legends</h2>'));
    expect(html, isNot(contains('## References')));
    expect(html, isNot(contains('## Figure legends')));
  });
}
