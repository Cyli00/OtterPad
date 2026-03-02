import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(DiscoverController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: const Center(child: Text('Discover Page')),
    );
  }
}
