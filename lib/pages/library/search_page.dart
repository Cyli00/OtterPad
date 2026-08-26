import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../services/haptics.dart';
import '../../providers/document_search_provider.dart';
import 'widgets/doc_card_actions.dart';
import 'widgets/doc_list_card.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    final l10n = context.l10n;
    // FTS5 检索（异步，ADR-0001：数据 provider 均为 DB 直读异步视图）。
    final asyncDocs = ref.watch(documentSearchProvider(_query));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                // 搜索栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          Haptics.soft();
                          context.pop();
                        },
                        icon: const Icon(Symbols.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: (v) => setState(() => _query = v.trim()),
                          decoration: InputDecoration(
                            hintText: l10n.searchDocumentsHintDesktop,
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
                              Symbols.search_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      Haptics.soft();
                                      _controller.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: Icon(
                                      Symbols.clear_rounded,
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
                                Symbols.search_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withAlpha(
                                  80,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.enterKeywordToSearch,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : asyncDocs.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: Text(
                              '$error',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                          data: (docs) => docs.isEmpty
                              ? Center(
                                  child: Text(
                                    l10n.noDocumentsFound,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    24,
                                  ),
                                  itemCount: docs.length,
                                  itemBuilder: (context, index) {
                                    final doc = docs[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: DocListCard(
                                        doc: doc,
                                        onTap: () => DocCardActions.openReader(
                                          context,
                                          ref,
                                          doc,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
