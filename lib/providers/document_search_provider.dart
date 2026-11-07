import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../data/models/book/document.dart';
import '../utils/debounced_action.dart';

/// 文献检索结果：Rust 合并 FTS5 中文分词/拼音与全字段子串匹配。
final documentSearchProvider = FutureProvider.autoDispose
    .family<List<Document>, String>((ref, query) async {
      ref.watch(libraryEpochProvider);
      if (query.trim().isEmpty) return const [];
      final debounce = DebouncedAction();
      final ready = Completer<bool>();
      debounce.run(() => ready.complete(true));
      ref.onDispose(() {
        debounce.cancel();
        if (!ready.isCompleted) ready.complete(false);
      });
      if (!await ready.future) return const [];
      final rows = await RustBackend.instance.searchLibrary(
        query: query.trim(),
        limit: 500,
      );
      return [for (final d in rows) documentFromRust(d)];
    });
