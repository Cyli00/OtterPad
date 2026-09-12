import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/l10n.dart';
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../core/storage/zotero_local_store.dart';
import '../data/models/book/document.dart';
import '../services/document_metadata_checks.dart';
import '../services/zotero_item_mapper.dart';
import '../services/zotero_sync_service.dart';
import '../utils/doc_paths.dart';
import 'document_lifecycle_provider.dart';

final zoteroSyncServiceProvider = Provider((ref) => ZoteroSyncService.instance);
final zoteroLocalImportProvider = Provider((ref) => ZoteroLocalImporter(ref));

class ZoteroLocalImportResult {
  int added = 0;
  int updated = 0;
  int copied = 0;
  int missing = 0;
  int kept = 0;
  final failedTitles = <String>[];
}

String zoteroLocalErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! ZoteroLocalException) return l10n.zoteroLocalFailed;
  return switch (error.reason) {
    ZoteroLocalFailure.unavailable => l10n.zoteroLocalUnavailable,
    ZoteroLocalFailure.disabled => l10n.zoteroLocalDisabled,
    ZoteroLocalFailure.incompatible => l10n.zoteroLocalIncompatible,
    ZoteroLocalFailure.changed => l10n.zoteroLocalChanged,
    ZoteroLocalFailure.invalidResponse => l10n.zoteroLocalInvalidResponse,
    ZoteroLocalFailure.invalidFile => l10n.zoteroLocalInvalidFile,
  };
}

class ZoteroLocalImporter {
  ZoteroLocalImporter(this.ref);
  final Ref ref;

  static Future<String> sourceIdentity(
    ZoteroLocalLibrary library,
    String? directory,
  ) async {
    if (library.serverId?.isNotEmpty == true) {
      return 'server:${library.serverId}:personal';
    }
    if (directory == null ||
        !await File(p.join(directory, 'zotero.sqlite')).exists()) {
      throw const ZoteroLocalException(ZoteroLocalFailure.invalidResponse);
    }
    final path = await Directory(directory).resolveSymbolicLinks();
    return 'directory:${p.style == p.Style.windows ? path.toLowerCase() : path}:personal';
  }

  Future<ZoteroLocalImportResult> run({
    required ZoteroLocalLibrary library,
    required String source,
    required List<ZoteroImportCandidate> candidates,
    required Map<String, String?> attachments,
    required CancelToken cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    final database = ref.read(appDatabaseProvider);
    final lifecycle = ref.read(documentLifecycleProvider);
    final api = ref.read(zoteroSyncServiceProvider);
    final store = ZoteroLocalStore(database);
    final result = ZoteroLocalImportResult();
    await api.verifyLocalLibrary(library, cancelToken: cancelToken);
    for (var i = 0; i < candidates.length; i++) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final candidate = candidates[i];
      try {
        final chosenAttachment = attachments[candidate.key];
        if (chosenAttachment != null &&
            !candidate.attachments.any((a) => a.key == chosenAttachment)) {
          throw const ZoteroLocalException(ZoteroLocalFailure.invalidResponse);
        }
        late String documentId;
        var added = false;
        var updated = false;
        await database.transaction(() async {
          final record = await store.read(source, candidate.key);
          Document? current;
          if (record != null) {
            final row = await (database.select(
              database.documents,
            )..where((t) => t.id.equals(record.documentId))).getSingleOrNull();
            if (row != null) current = documentFromRow(row);
          }
          final hasRecord = current != null;
          if (current == null) {
            final before = await database.select(database.documents).get();
            current = (await lifecycle.importDocuments([
              candidate.document,
            ])).single;
            added = !before.any((row) => row.id == current!.id);
          }
          documentId = current.id;
          final merged = await lifecycle.mergeSourceMetadata(
            documentId,
            candidate.document,
            hasRecord ? record!.metadata : null,
          );
          if (merged == null) throw StateError('document_removed');
          if (!DocumentMetadataChecks.sameCore(current, merged) ||
              current.keywords.join('\u0000') !=
                  merged.keywords.join('\u0000')) {
            updated = true;
          }
          await store.write(
            source,
            candidate.key,
            ZoteroLocalRecord(
              documentId,
              candidate.document,
              hasRecord ? record!.attachmentKey : null,
            ),
          );
        });
        if (added) result.added++;
        if (updated) result.updated++;
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (chosenAttachment != null) {
          if (await File(DocPaths.pdf(documentId)).exists()) {
            result.kept++;
          } else {
            final uri = await api.localAttachmentUri(
              library,
              chosenAttachment,
              cancelToken: cancelToken,
            );
            final path = uri?.replace(host: '').toFilePath();
            if (path == null || !await File(path).exists()) {
              result.missing++;
            } else if (await lifecycle.attachMissingPdf(
              documentId,
              path,
              cancelToken: cancelToken,
            )) {
              result.copied++;
              await store.write(
                source,
                candidate.key,
                ZoteroLocalRecord(
                  documentId,
                  candidate.document,
                  chosenAttachment,
                ),
              );
            } else {
              result.kept++;
            }
          }
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        result.failedTitles.add(candidate.document.title);
      } on ZoteroLocalException catch (e) {
        if (e.reason == ZoteroLocalFailure.changed ||
            e.reason == ZoteroLocalFailure.unavailable ||
            e.reason == ZoteroLocalFailure.disabled) {
          rethrow;
        }
        result.failedTitles.add(candidate.document.title);
      } catch (_) {
        result.failedTitles.add(candidate.document.title);
      }
      onProgress?.call(i + 1, candidates.length);
    }
    return result;
  }
}
