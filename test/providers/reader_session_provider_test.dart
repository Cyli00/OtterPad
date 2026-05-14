import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/reader_session_provider.dart';

void main() {
  group('ReaderSessionState', () {
    test('根据字符偏移计算 Markdown 块索引', () {
      const markdown = '标题\n\n第一段\n\n第二段\n\n第三段';
      const state = ReaderSessionState(markdownContent: markdown);

      expect(state.blockIndexForCharOffset(0), 0);
      expect(state.blockIndexForCharOffset(markdown.indexOf('第二段')), 2);
      expect(state.blockIndexForCharOffset(markdown.length + 20), 3);
    });

    test('从偏移附近提取图片文件名', () {
      const markdown = '正文\n\n![Figure 1](figures/Figure_1.png)\n\n后续正文';
      const state = ReaderSessionState(markdownContent: markdown);

      expect(state.imageFilenameNearOffset(0), 'Figure_1.png');
      expect(state.imageFilenameNearOffset(markdown.length), isNull);
    });

    test('为短选择扩展到所在段落上下文', () {
      const markdown = '第一段包含关键发现和更多背景。\n\n第二段继续说明机制。';
      const state = ReaderSessionState(markdownContent: markdown);

      expect(state.expandToParagraphContext('关键发现'), '第一段包含关键发现和更多背景。');
      expect(state.expandToParagraphContext('第二段继续说明机制。'), isNull);
    });
  });
}
