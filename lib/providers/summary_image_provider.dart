import 'dart:io';

import 'package:flutter_riverpod/legacy.dart';

import '../services/document_summary_image_service.dart';

class SummaryImageState {
  final String? imagePath;
  final int revision;
  final bool generating;

  const SummaryImageState({
    this.imagePath,
    this.revision = 0,
    this.generating = false,
  });

  SummaryImageState copyWith({
    String? imagePath,
    int? revision,
    bool? generating,
  }) {
    return SummaryImageState(
      imagePath: imagePath ?? this.imagePath,
      revision: revision ?? this.revision,
      generating: generating ?? this.generating,
    );
  }
}

class SummaryImageNotifier extends StateNotifier<SummaryImageState> {
  final String pdfPath;

  SummaryImageNotifier(this.pdfPath) : super(_load(pdfPath));

  static SummaryImageState _load(String pdfPath) {
    if (pdfPath.isEmpty) return const SummaryImageState();
    final imagePath = DocumentSummaryImageService.imagePathFor(pdfPath);
    return SummaryImageState(
      imagePath: File(imagePath).existsSync() ? imagePath : null,
    );
  }

  void start() {
    final currentPath = pdfPath.isEmpty
        ? state.imagePath
        : DocumentSummaryImageService.imagePathFor(pdfPath);
    state = SummaryImageState(
      imagePath: File(currentPath ?? '').existsSync()
          ? currentPath
          : state.imagePath,
      revision: state.revision,
      generating: true,
    );
  }

  void generated(String imagePath) {
    state = SummaryImageState(
      imagePath: imagePath,
      revision: state.revision + 1,
    );
  }

  void finishWithoutImage() {
    state = state.copyWith(generating: false);
  }

  Future<void> syncFromDisk() async {
    if (pdfPath.isEmpty) {
      finishWithoutImage();
      return;
    }
    final imagePath = DocumentSummaryImageService.imagePathFor(pdfPath);
    if (await File(imagePath).exists()) {
      generated(imagePath);
    } else {
      finishWithoutImage();
    }
  }
}

final summaryImageProvider =
    StateNotifierProvider.family<
      SummaryImageNotifier,
      SummaryImageState,
      String
    >((ref, pdfPath) => SummaryImageNotifier(pdfPath));
