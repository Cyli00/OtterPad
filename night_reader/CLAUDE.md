# NightReader — 项目规范与架构文档

## 项目简介

NightReader 是一款基于 Flutter 的跨平台阅读应用，目标是提供类似 Zotero 的文献/书籍管理能力，并以 Material Design 3 为 UI 规范。

**参考项目：**
- 功能/数据层参考：`ref/zotero-android`（Kotlin，Compose）
- UI/页面结构参考：`ref/PiliPlus`（Flutter + GetX）

---

## 技术选型

| 关注点 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x | 跨平台（Android/iOS/Desktop） |
| 状态管理 | GetX | 参考 PiliPlus；Controller + View 模式 |
| 本地数据库 | Isar | 替代 zotero-android 的 Realm；纯 Dart，速度快 |
| 键值存储 | Hive + hive_flutter | 设置项、偏好 |
| 网络 | Dio | HTTP 客户端，支持拦截器 |
| 路由 | GetX 路由（app_pages.dart）| 参考 PiliPlus 模式 |
| UI 主题 | Material Design 3 + dynamic_color | Material You 动态取色 |
| PDF 阅读 | pdfx / syncfusion_flutter_pdfviewer | 待评估 |
| EPUB 阅读 | epub_view | 待评估 |
| 同步 | webdav_client | 参考 zotero-android 的 WebDAV 同步 |
| 代码生成 | build_runner + json_serializable | 模型序列化 |
| 图片缓存 | cached_network_image | |
| 文件路径 | path_provider | |
| 日志 | logger | 参考 PiliPlus |
| Toast/对话框 | flutter_smart_dialog | 参考 PiliPlus |
| 下载 | 自定义 DownloadService | 参考 PiliPlus services/download |

---

## 整体分层架构

```
Flutter App
│
├── UI 层（前端）         → lib/pages/ + lib/common/
│   ├── 页面（Page）       每页含 view.dart + controller.dart（GetX）
│   └── 公共组件（Widget）  lib/common/widgets/ + skeleton/
│
├── 服务层（Service）     → lib/services/
│   ├── 下载服务
│   ├── 同步服务（后台同步）
│   └── 文件解析服务（epub/pdf）
│
├── 数据层（后端）        → lib/data/ + lib/core/
│   ├── Repository        统一数据访问接口
│   ├── 本地数据源         Isar DB
│   ├── 远程数据源         REST API / WebDAV
│   └── 同步引擎           lib/data/sync/
│
└── 基础设施（Core）      → lib/core/
    ├── 数据库初始化
    ├── 网络客户端
    ├── 键值存储
    └── 依赖注入（GetX）
```

---

## lib/ 目录结构

```
lib/
│
├── main.dart                          # 入口，初始化 Hive/Isar/GetX
├── app.dart                           # MaterialApp，主题，路由
│
├── core/                              # 基础设施层（无业务逻辑）
│   ├── database/
│   │   ├── database.dart              # Isar 初始化
│   │   ├── objects/                   # Isar 实体（@Collection）
│   │   └── requests/                  # Isar 查询封装
│   ├── network/
│   │   ├── dio_client.dart            # Dio 单例，全局拦截器
│   │   └── interceptors/
│   │       ├── auth_interceptor.dart
│   │       └── log_interceptor.dart
│   ├── storage/
│   │   ├── storage.dart               # Hive 初始化
│   │   ├── storage_key.dart           # 存储 Key 常量
│   │   └── storage_pref.dart          # 类型安全的 Pref 访问
│   └── services/
│       ├── service_locator.dart       # GetX 依赖注入入口
│       └── logger.dart
│
├── data/                              # 数据层
│   ├── models/                        # 纯数据模型（json_serializable）
│   │   ├── book/
│   │   │   ├── book_item.dart
│   │   │   └── book_item.g.dart
│   │   ├── annotation/
│   │   │   └── annotation_item.dart
│   │   ├── collection/
│   │   │   └── collection_item.dart
│   │   └── common/
│   │       └── result.dart            # 通用 Result<T, E>
│   ├── repositories/                  # Repository 接口 + 实现
│   │   ├── book_repository.dart
│   │   ├── annotation_repository.dart
│   │   ├── collection_repository.dart
│   │   └── sync_repository.dart
│   ├── sources/
│   │   ├── local/                     # Isar 数据源
│   │   │   ├── book_local_source.dart
│   │   │   └── annotation_local_source.dart
│   │   └── remote/                    # REST/WebDAV 数据源
│   │       ├── book_remote_source.dart
│   │       └── webdav_source.dart
│   └── sync/                          # 同步引擎（参考 zotero-android/sync）
│       ├── sync_controller.dart       # 同步流程编排
│       ├── sync_state.dart            # 同步状态枚举
│       ├── webdav/
│       │   └── webdav_sync.dart
│       └── conflict_resolver.dart     # 冲突解决策略
│
├── pages/                             # 功能页面（PiliPlus 模式）
│   │                                  # 每个页面：view.dart + controller.dart
│   ├── main/                          # 主导航 Shell（BottomNavigationBar/Rail）
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── library/                       # 书库（所有书籍列表）
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── shelf/                         # 书架/收藏集管理（类 Zotero Collections）
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── reader/                        # 阅读界面（PDF/EPUB）
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── annotation/                    # 批注列表
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── search/                        # 搜索（书库内搜索 + 在线发现）
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── discover/                      # 发现/推荐
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── download/                      # 下载管理
│   │   ├── view.dart
│   │   └── controller.dart
│   ├── setting/                       # 设置
│   │   ├── view.dart
│   │   └── controller.dart
│   └── login/                         # 登录/账户
│       ├── view.dart
│       └── controller.dart
│
├── common/                            # 共用 UI 组件（PiliPlus 模式）
│   ├── widgets/
│   │   ├── book_card.dart             # 书籍卡片
│   │   ├── empty_view.dart            # 空状态
│   │   ├── error_view.dart            # 错误状态
│   │   ├── loading_indicator.dart
│   │   └── network_image.dart         # 封面图片
│   ├── skeleton/                      # 加载骨架屏
│   │   └── book_card_skeleton.dart
│   └── theme/
│       ├── app_theme.dart             # ThemeData（Light/Dark/M3）
│       └── color_scheme.dart          # 动态取色 fallback
│
├── services/                          # 应用级后台服务
│   ├── download/
│   │   ├── download_service.dart      # 下载队列管理
│   │   └── download_task.dart         # 单任务模型
│   ├── reader/
│   │   ├── epub_parser.dart           # EPUB 解析
│   │   └── pdf_handler.dart           # PDF 处理
│   └── sync_service.dart              # 后台同步调度
│
├── router/                            # 路由（PiliPlus 模式）
│   ├── app_pages.dart                 # GetPage 路由表
│   └── app_routes.dart                # 路由路径常量
│
└── utils/                             # 工具函数（PiliPlus 模式）
    ├── storage.dart                   # GStorage 单例
    ├── storage_key.dart
    ├── storage_pref.dart
    ├── date_utils.dart
    ├── file_utils.dart
    ├── format_utils.dart              # 文件大小、进度等格式化
    ├── theme_utils.dart
    └── extension/
        ├── string_ext.dart
        ├── context_ext.dart
        └── get_ext.dart
```

---

## assets/ 目录结构

```
assets/
├── fonts/                   # 自定义字体
├── images/
│   └── logo/
└── icons/                   # SVG 图标
```

---

## 编码规范

### 页面开发模式（参考 PiliPlus）

每个功能页面包含两个文件：

```dart
// pages/library/controller.dart
class LibraryController extends GetxController {
  // 状态
  final RxList<BookItem> books = <BookItem>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadBooks();
  }

  Future<void> loadBooks() async { ... }
}

// pages/library/view.dart
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.putOrFind(LibraryController.new);
    return Scaffold( ... );
  }
}
```

### 数据层模式（参考 zotero-android）

- Repository 对 UI 层隐藏数据来源（本地/远程/缓存）
- 所有数据库访问通过 `core/database/requests/` 封装
- 同步结果通过 `sync/conflict_resolver.dart` 处理冲突

### 命名规范

- 文件名：`snake_case.dart`
- 类名：`PascalCase`
- 常量：`camelCase`（Dart 惯例）
- GetX Controller：`XxxController extends GetxController`
- 页面 Widget：`XxxPage extends StatelessWidget`

---

## 关键包（待加入 pubspec.yaml）

```yaml
dependencies:
  get: ^4.6.6                    # 状态管理 + 路由 + DI
  dio: ^5.x                      # HTTP
  isar: ^3.x                     # 本地数据库
  isar_flutter_libs: ^3.x
  hive_flutter: ^1.x             # 键值存储
  dynamic_color: ^1.x            # Material You
  webdav_client: ^1.x            # WebDAV 同步
  cached_network_image: ^3.x
  path_provider: ^2.x
  flutter_smart_dialog: ^4.x     # Toast / Dialog
  logger: ^2.x
  share_plus: ^9.x
  permission_handler: ^11.x
  package_info_plus: ^8.x
  intl: ^0.19.x
  json_annotation: ^4.x
  archive: ^3.x                  # zip/epub 解压

dev_dependencies:
  build_runner: ^2.x
  json_serializable: ^6.x
  isar_generator: ^3.x
```

---

## 同步架构（参考 zotero-android/sync）

```
SyncService（后台调度）
  └── SyncController（流程编排）
        ├── 1. 拉取远端变更（WebDAV / REST API）
        ├── 2. 合并本地变更（ConflictResolver）
        ├── 3. 推送本地变更
        └── 4. 更新 SyncState（RxEnum）

SyncState: idle → syncing → success / error
```

---

## 参考文件位置

- `ref/zotero-android/app/src/main/java/org/zotero/android/sync/` — 同步逻辑
- `ref/zotero-android/app/src/main/java/org/zotero/android/database/` — DB 分层
- `ref/PiliPlus/lib/pages/home/` — Controller + View 模式示例
- `ref/PiliPlus/lib/services/` — 服务层示例
- `ref/PiliPlus/lib/router/app_pages.dart` — 路由注册
- `ref/PiliPlus/pubspec.yaml` — 完整包参考
