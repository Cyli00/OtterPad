import '../data/models/book/document.dart';
import 'document_metadata_checks.dart';

/// 批次内按 DOI 和规范标题缩小候选集，最终仍沿用原判重规则。
class DocumentDuplicateIndex {
  DocumentDuplicateIndex(Iterable<Document> documents) {
    for (final document in documents) {
      put(document);
    }
  }

  final _documents = <String, Document>{};
  final _doi = <String, Set<String>>{};
  final _title = <String, Set<String>>{};

  void put(Document document) {
    final old = _documents[document.id];
    if (old != null) {
      _doi[old.doi?.toLowerCase()]?.remove(old.id);
      _title[DocumentMetadataChecks.normalizeComparisonKey(old.title)]?.remove(
        old.id,
      );
    }
    _documents[document.id] = document;
    if (!DocumentMetadataChecks.isBlank(document.doi)) {
      (_doi[document.doi!.toLowerCase()] ??= {}).add(document.id);
    }
    (_title[DocumentMetadataChecks.normalizeComparisonKey(document.title)] ??=
            {})
        .add(document.id);
  }

  Document? find(Document candidate) {
    final ids = <String>{
      ...?_doi[candidate.doi?.toLowerCase()],
      ...?_title[DocumentMetadataChecks.normalizeComparisonKey(
        candidate.title,
      )],
    };
    for (final id in ids) {
      final document = _documents[id]!;
      if (DocumentMetadataChecks.isDuplicate(document, candidate)) {
        return document;
      }
    }
    return null;
  }
}
