import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(DownloadController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Download')),
      body: const Center(child: Text('Download Page')),
    );
  }
}
