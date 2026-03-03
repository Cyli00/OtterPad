/// 全局依赖注入入口
/// 在 main() 中调用 ServiceLocator.init()
class ServiceLocator {
  static Future<void> init() async {
    // 注册核心服务（懒加载）
    // Get.lazyPut<SyncService>(() => SyncService());
    // Get.lazyPut<DownloadService>(() => DownloadService());
  }
}
