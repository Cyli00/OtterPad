import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';

import 'controller.dart';

class AnnotationPage extends StatelessWidget {
  const AnnotationPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.putOrFind(AnnotationController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Annotation')),
      body: const Center(child: Text('Annotation Page')),
    );
  }
}
