import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(MainController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Main')),
      body: const Center(child: Text('Main Page')),
    );
  }
}
