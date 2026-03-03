import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';

import 'controller.dart';

class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.putOrFind(ReaderController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: const Center(child: Text('Reader Page')),
    );
  }
}
