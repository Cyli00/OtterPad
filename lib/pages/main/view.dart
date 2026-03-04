import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/adaptive_navigation.dart';
import '../library/view.dart';
import '../shelf/view.dart';
import '../setting/view.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _currentIndex = 0;

  void _onDestinationSelected(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      selectedIndex: _currentIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: const [
        AdaptiveDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        AdaptiveDestination(
          icon: Icon(Icons.folder_copy_outlined),
          selectedIcon: Icon(Icons.folder_copy),
          label: '库',
        ),
        AdaptiveDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          LibraryPage(),
          ShelfPage(),
          SettingPage(),
        ],
      ),
    );
  }
}
