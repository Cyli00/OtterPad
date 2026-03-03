import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';

import 'controller.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.putOrFind(DownloadController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Download')),
      body: const Center(child: Text('Download Page')),
    );
  }
}
