import 'package:flutter/material.dart';

class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shelf')),
      body: const Center(child: Text('Shelf Page')),
    );
  }
}
