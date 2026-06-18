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

  // 设置子页面
  static const settingsNetwork = '/settings/network';
  static const settingsApi = '/settings/api';
  static const settingsExtract = '/settings/extract';
  static const settingsAppearance = '/settings/appearance';
  static const settingsBackup = '/settings/backup';
  static const settingsBackupHome = '/settings/backupHome';
  static const settingsStorage = '/settings/storage';
  static const settingsGeneral = '/settings/general';
  static const settingsAbout = '/settings/about';
}
