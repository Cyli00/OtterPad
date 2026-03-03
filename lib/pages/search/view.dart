import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';

import 'controller.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.putOrFind(SearchPageController.new);
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: const Center(child: Text('Search Page')),
    );
  }
}
