import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/data/models/book/highlight.dart';
import 'package:otter_pad/pages/reader/widgets/reader_background.dart';
import 'package:otter_pad/pages/reader/widgets/reader_update_plan.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';

void main() {
  const basePalette = ReaderPalette(
    background: Colors.white,
    text: Colors.black,
    secondaryText: Colors.black54,
    link: Colors.blue,
    divider: Colors.black12,
    codeBlock: Color(0xFFF5F5F5),
  );

  ReaderProps props({
    String markdownData = 'md',
    int contentRevision = 0,
    ReaderPalette palette = basePalette,
    ReaderSettingsState settings = const ReaderSettingsState(),
    String translationStyleId = 'themed',
    List<Highlight> highlights = const [],
    String? highlightQuery,
  }) => ReaderProps(
    markdownData: markdownData,
    contentRevision: contentRevision,
    palette: palette,
    settings: settings,
    translationStyleId: translationStyleId,
    highlights: highlights,
    highlightQuery: highlightQuery,
  );

  Highlight hl(String id) => Highlight(
    id: id,
    documentId: 'doc',
    text: 't',
    createdAt: DateTime(2024),
  );

  test('无任何变化 → 空清单', () {
    expect(planUpdates(props(), props()), isEmpty);
  });

  test('正文相同但排版版本变化时重写 HTML', () {
    final updates = planUpdates(props(), props(contentRevision: 1));
    expect(updates, hasLength(1));
    expect(updates.single, isA<ReloadContent>());
  });

  test('字号变化 → ApplyTheme', () {
    final updates = planUpdates(
      props(),
      props(settings: const ReaderSettingsState(fontSize: 18)),
    );
    expect(updates, hasLength(1));
    expect(updates.single, isA<ApplyTheme>());
  });

  test('data 变化 → 只 ReloadContent，即使同时改了主题', () {
    final updates = planUpdates(
      props(),
      props(
        markdownData: 'new',
        settings: const ReaderSettingsState(fontSize: 18),
      ),
    );
    // 关键守卫：data 变了就只 reload，主题/翻页/翻译/高亮都不单独应用。
    expect(updates, hasLength(1));
    expect(updates.single, isA<ReloadContent>());
  });

  test('data 变化时 highlightQuery 仍然应用（不受 data 守卫约束）', () {
    final updates = planUpdates(
      props(),
      props(markdownData: 'new', highlightQuery: 'gene'),
    );
    expect(updates, hasLength(2));
    expect(updates[0], isA<ReloadContent>());
    expect(updates[1], isA<ApplySearchQuery>());
  });

  test('翻页方式变化 → ApplyPagination 携带新模式', () {
    final updates = planUpdates(
      props(),
      props(
        settings: const ReaderSettingsState(
          paginationMode: ReaderPaginationMode.horizontal,
        ),
      ),
    );
    expect(updates, hasLength(1));
    expect(
      updates.single,
      isA<ApplyPagination>().having(
        (u) => u.mode,
        'mode',
        ReaderPaginationMode.horizontal,
      ),
    );
  });

  test('翻译样式变化 → ApplyTranslationStyle 携带新 id', () {
    final updates = planUpdates(props(), props(translationStyleId: 'bold'));
    expect(updates, hasLength(1));
    expect(
      updates.single,
      isA<ApplyTranslationStyle>().having((u) => u.styleId, 'styleId', 'bold'),
    );
  });

  test('高亮列表变化（不同实例）→ SyncHighlights 携带新旧两份', () {
    final oldList = [hl('a')];
    final newList = [hl('a'), hl('b')];
    final updates = planUpdates(
      props(highlights: oldList),
      props(highlights: newList),
    );
    expect(updates, hasLength(1));
    final u = updates.single;
    expect(u, isA<SyncHighlights>());
    u as SyncHighlights;
    expect(u.oldHighlights, same(oldList));
    expect(u.newHighlights, same(newList));
  });

  test('仅 query 变化 → ApplySearchQuery 携带新 query', () {
    final updates = planUpdates(props(), props(highlightQuery: 'tumor'));
    expect(updates, hasLength(1));
    expect(
      updates.single,
      isA<ApplySearchQuery>().having((u) => u.query, 'query', 'tumor'),
    );
  });

  test('多项同时变化（无 data）→ 保持固定顺序', () {
    final oldList = [hl('a')];
    final newList = <Highlight>[];
    final updates = planUpdates(
      props(highlights: oldList),
      props(
        settings: const ReaderSettingsState(
          fontSize: 18,
          paginationMode: ReaderPaginationMode.horizontal,
        ),
        translationStyleId: 'bold',
        highlights: newList,
        highlightQuery: 'q',
      ),
    );
    expect(updates.map((u) => u.runtimeType).toList(), [
      ApplyTheme,
      ApplyPagination,
      ApplyTranslationStyle,
      SyncHighlights,
      ApplySearchQuery,
    ]);
  });
}
