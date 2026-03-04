import 'package:flutter/material.dart';

class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: const Center(child: Text('Reader Page')),
    );
  }
}
