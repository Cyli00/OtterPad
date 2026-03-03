import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';

import 'controller.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.putOrFind(SettingController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Setting')),
      body: const Center(child: Text('Setting Page')),
    );
  }
}
