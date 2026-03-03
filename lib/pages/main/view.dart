import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:night_reader/utils/extension/get_ext.dart';
import '../library/view.dart';
import '../shelf/view.dart';
import '../setting/view.dart';

import 'controller.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(MainController.new);
    return Scaffold(
      body: PageView(
        physics: const NeverScrollableScrollPhysics(),
        controller: controller.pageController,
        children: const [
          LibraryPage(),
          ShelfPage(),
          SettingPage(),
        ],
      ),
      bottomNavigationBar: Obx(
        () => _buildBottomNavBar(context, controller),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context, MainController controller) {
    return NavigationBar(
      selectedIndex: controller.selectedIndex.value,
      onDestinationSelected: controller.setIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_copy_outlined),
          selectedIcon: Icon(Icons.folder_copy),
          label: '库',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }
}
