import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/documents_provider.dart';
import 'widgets/pdf_cover.dart';

/// 文献搜索页面
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final docs = ref.watch(documentsProvider);
    final filtered =
        _query.isEmpty ? [] : docs.where((d) => d.matchesQuery(_query)).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: InputDecoration(
                        hintText: '搜索文献、作者、关键词...',
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest
                            .withAlpha(150),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  setState(() => _query = '');
                                },
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 搜索结果
            Expanded(
              child: _query.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 64,
                            color:
                                colorScheme.onSurfaceVariant.withAlpha(80),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '输入关键词搜索文献',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            '未找到匹配的文献',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            return Card(
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              color: colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  // TODO: 打开 PDF 阅读器
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // 缩略图
                                      if (doc.filePath.isNotEmpty)
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8),
                                          child: SizedBox(
                                            width: 56,
                                            height: 76,
                                            child: PdfCoverRender(
                                              assetPath:
                                                  doc.filePath,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 56,
                                          height: 76,
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(
                                                    8),
                                          ),
                                          child: Icon(
                                            Icons.picture_as_pdf,
                                            color: colorScheme
                                                .onSurfaceVariant
                                                .withAlpha(100),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      // 文献信息
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                              doc.title,
                                              style: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                fontWeight:
                                                    FontWeight.bold,
                                                height: 1.25,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow
                                                  .ellipsis,
                                            ),
                                            if (doc.authors
                                                .isNotEmpty) ...[
                                              const SizedBox(
                                                  height: 4),
                                              Text(
                                                doc.authors
                                                    .join(', '),
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                              ),
                                            ],
                                            if (doc.year != null) ...[
                                              const SizedBox(
                                                  height: 2),
                                              Text(
                                                [
                                                  if (doc.journal !=
                                                      null)
                                                    doc.journal!,
                                                  doc.year!,
                                                ].join(' · '),
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant
                                                      .withAlpha(
                                                          160),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
