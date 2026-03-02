import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(ShelfController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Shelf')),
      body: const Center(child: Text('Shelf Page')),
    );
  }
}
