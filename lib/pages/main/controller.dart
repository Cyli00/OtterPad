import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MainController extends GetxController {
  late final PageController pageController;
  final RxInt selectedIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    pageController = PageController(initialPage: selectedIndex.value);
  }

  void setIndex(int index) {
    if (selectedIndex.value != index) {
      selectedIndex.value = index;
      pageController.jumpToPage(index);
    }
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
