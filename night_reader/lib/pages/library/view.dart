import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(LibraryController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: const Center(child: Text('Library Page')),
    );
  }
}
