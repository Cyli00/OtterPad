import 'package:flutter/material.dart';

class AnnotationPage extends StatelessWidget {
  const AnnotationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Annotation')),
      body: const Center(child: Text('Annotation Page')),
    );
  }
}
