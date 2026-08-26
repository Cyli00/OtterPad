import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/reader_session_provider.dart';

void main() {
  group('ReaderSessionState', () {
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

    test('copyWith 保留 dockOpen', () {
      const state = ReaderSessionState();
      expect(state.dockOpen, isFalse);
      expect(state.copyWith(dockOpen: true).dockOpen, isTrue);
      expect(
        state.copyWith(dockOpen: true).copyWith(sheetOpen: true).dockOpen,
        isTrue,
      );
    });
  });
}
