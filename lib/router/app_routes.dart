abstract class AppRoutes {
  static const library = '/library';
  static const shelf = '/shelf';
  static const settings = '/settings';
  static const reader = '/reader';

  // 阅读器子页面
  static const readerChat = '/reader/chat';

  // 文献库子页面
  static const librarySearch = '/library/search';

  // 书架子页面
  static const shelfFavorite = '/shelf/favorite';
  static const shelfFavoriteAddDocs = '/shelf/favorite/add-documents';
  static const shelfHistory = '/shelf/history';
  static const shelfNoFileEntries = '/shelf/no-file-entries';
  static const shelfCloudSync = '/shelf/cloud-sync';

  // overlay 设置（root 平级 GoRoute）
  static const settingsOverlay = '/settings-overlay';
  static const settingsOverlayGeneral = '/settings-overlay/general';
  static const settingsOverlayNetwork = '/settings-overlay/network';
  static const settingsOverlayApi = '/settings-overlay/api';
  static const settingsOverlayExtract = '/settings-overlay/extract';
  static const settingsOverlayAppearance = '/settings-overlay/appearance';
  static const settingsOverlayBackup = '/settings-overlay/backup';
  static const settingsOverlayStorage = '/settings-overlay/storage';
  static const settingsOverlayAbout = '/settings-overlay/about';
}
