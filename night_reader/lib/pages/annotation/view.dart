import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

class AnnotationPage extends StatelessWidget {
  const AnnotationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(AnnotationController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Annotation')),
      body: const Center(child: Text('Annotation Page')),
    );
  }
}
