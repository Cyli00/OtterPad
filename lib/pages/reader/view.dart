import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../data/models/book/document.dart';

class ReaderPage extends StatelessWidget {
  final Document document;

  const ReaderPage({
    super.key,
    required this.document,
  });

  @override
  Widget build(BuildContext context) {
    final fileExists =
        document.filePath.isNotEmpty && File(document.filePath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: 可以在这里添加查阅文献元数据的入口
            },
          ),
        ],
      ),
      body: fileExists
          ? PdfViewer.file(
              document.filePath,
              params: const PdfViewerParams(
                backgroundColor: Colors.transparent,
              ),
            )
          : const Center(
              child: Text('找不到该文献的 PDF 文件'),
            ),
    );
  }
}
