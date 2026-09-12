import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/reader/reader_document_index.dart';

typedef ReaderIndexArgs = ({String documentId, String markdown, int revision});

final readerDocumentIndexProvider = FutureProvider.autoDispose
    .family<ReaderDocumentIndex, ReaderIndexArgs>(
      (ref, args) => ReaderDocumentIndex.load(args.documentId, args.markdown),
    );
