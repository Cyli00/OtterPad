// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';

enum BackupRemoteType {
  s3('S3'),
  webdav('WebDAV');

  const BackupRemoteType(this.label);

  final String label;
}

class BackupWebDavState {
  static const defaultRemoteDir = '/OtterPad';
  static const defaultFileName = 'otter_pad_backup.zip';

  final String serverUrl;
  final String username;
  final String password;
  final String remoteDir;
  final String fileName;

  const BackupWebDavState({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = defaultRemoteDir,
    this.fileName = defaultFileName,
  });

  BackupWebDavState copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDir,
    String? fileName,
  }) {
    return BackupWebDavState(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
      fileName: fileName ?? this.fileName,
    );
  }

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  String get remoteFilePath {
    final normalizedDir = _normalizeRemoteDir(remoteDir);
    return '$normalizedDir/${fileName.trim().isEmpty ? defaultFileName : fileName.trim()}';
  }

  static String _normalizeRemoteDir(String value) {
    final trimmed = value.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) return defaultRemoteDir;
    final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    final collapsed = normalized
        .replaceAll(RegExp('/+'), '/')
        .replaceFirst(RegExp(r'/$'), '');
    return collapsed.isEmpty ? '/' : collapsed;
  }
}

class BackupS3State {
  static const defaultEndpoint = 'https://s3.amazonaws.com';
  static const defaultRegion = 'us-east-1';
  static const defaultObjectKey = 'otter-pad/otter_pad_backup.zip';

  final String endpoint;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String objectKey;
  final bool usePathStyle;

  const BackupS3State({
    this.endpoint = defaultEndpoint,
    this.region = defaultRegion,
    this.bucket = '',
    this.accessKeyId = '',
    this.secretAccessKey = '',
    this.objectKey = defaultObjectKey,
    this.usePathStyle = true,
  });

  BackupS3State copyWith({
    String? endpoint,
    String? region,
    String? bucket,
    String? accessKeyId,
    String? secretAccessKey,
    String? objectKey,
    bool? usePathStyle,
  }) {
    return BackupS3State(
      endpoint: endpoint ?? this.endpoint,
      region: region ?? this.region,
      bucket: bucket ?? this.bucket,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
      objectKey: objectKey ?? this.objectKey,
      usePathStyle: usePathStyle ?? this.usePathStyle,
    );
  }

  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      region.trim().isNotEmpty &&
      bucket.trim().isNotEmpty &&
      accessKeyId.trim().isNotEmpty &&
      secretAccessKey.isNotEmpty;

  String get normalizedEndpoint {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) return defaultEndpoint;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed.replaceFirst(RegExp(r'/$'), '');
    }
    return 'https://${trimmed.replaceFirst(RegExp(r'/$'), '')}';
  }

  String get normalizedObjectKey {
    final trimmed = objectKey.trim().replaceAll('\\', '/');
    final normalized = trimmed.isEmpty ? defaultObjectKey : trimmed;
    return normalized.replaceAll(RegExp('^/+'), '');
  }
}

class BackupRemoteTypeNotifier extends StateNotifier<BackupRemoteType> {
  static const _remoteTypeKey = 'backup_remote_type';

  BackupRemoteTypeNotifier() : super(_load());

  static BackupRemoteType _load() {
    final box = GStorage.setting;
    final saved =
        box.get(_remoteTypeKey, defaultValue: BackupRemoteType.s3.name)
            as String;
    return BackupRemoteType.values.firstWhere(
      (type) => type.name == saved,
      orElse: () => BackupRemoteType.s3,
    );
  }

  Future<void> setRemoteType(BackupRemoteType type) async {
    state = type;
    await GStorage.setting.put(_remoteTypeKey, type.name);
  }

  void reload() {
    state = _load();
  }
}

class BackupWebDavNotifier extends StateNotifier<BackupWebDavState> {
  static const _serverUrlKey = 'backup_webdav_server_url';
  static const _usernameKey = 'backup_webdav_username';
  static const _passwordKey = 'backup_webdav_password';
  static const _remoteDirKey = 'backup_webdav_remote_dir';
  static const _fileNameKey = 'backup_webdav_file_name';

  BackupWebDavNotifier() : super(_load());

  static BackupWebDavState _load() {
    final box = GStorage.setting;
    return BackupWebDavState(
      serverUrl: box.get(_serverUrlKey, defaultValue: '') as String,
      username: box.get(_usernameKey, defaultValue: '') as String,
      password: SecureCredentialVault.read(_passwordKey),
      remoteDir:
          box.get(
                _remoteDirKey,
                defaultValue: BackupWebDavState.defaultRemoteDir,
              )
              as String,
      fileName:
          box.get(_fileNameKey, defaultValue: BackupWebDavState.defaultFileName)
              as String,
    );
  }

  Future<void> save(BackupWebDavState next) async {
    final normalized = next.copyWith(
      remoteDir: BackupWebDavState._normalizeRemoteDir(next.remoteDir),
      fileName: next.fileName.trim().isEmpty
          ? BackupWebDavState.defaultFileName
          : next.fileName.trim(),
    );
    state = normalized;
    await Future.wait([
      GStorage.setting.put(_serverUrlKey, normalized.serverUrl.trim()),
      GStorage.setting.put(_usernameKey, normalized.username.trim()),
      SecureCredentialVault.write(_passwordKey, normalized.password),
      GStorage.setting.put(_remoteDirKey, normalized.remoteDir),
      GStorage.setting.put(_fileNameKey, normalized.fileName),
    ]);
  }

  void reload() {
    state = _load();
  }
}

class BackupS3Notifier extends StateNotifier<BackupS3State> {
  static const _endpointKey = 'backup_s3_endpoint';
  static const _regionKey = 'backup_s3_region';
  static const _bucketKey = 'backup_s3_bucket';
  static const _accessKeyIdKey = 'backup_s3_access_key_id';
  static const _secretAccessKeyKey = 'backup_s3_secret_access_key';
  static const _objectKeyKey = 'backup_s3_object_key';
  static const _usePathStyleKey = 'backup_s3_use_path_style';

  BackupS3Notifier() : super(_load());

  static BackupS3State _load() {
    final box = GStorage.setting;
    return BackupS3State(
      endpoint:
          box.get(_endpointKey, defaultValue: BackupS3State.defaultEndpoint)
              as String,
      region:
          box.get(_regionKey, defaultValue: BackupS3State.defaultRegion)
              as String,
      bucket: box.get(_bucketKey, defaultValue: '') as String,
      accessKeyId: box.get(_accessKeyIdKey, defaultValue: '') as String,
      secretAccessKey: SecureCredentialVault.read(_secretAccessKeyKey),
      objectKey:
          box.get(_objectKeyKey, defaultValue: BackupS3State.defaultObjectKey)
              as String,
      usePathStyle: box.get(_usePathStyleKey, defaultValue: true) as bool,
    );
  }

  Future<void> save(BackupS3State next) async {
    final normalized = next.copyWith(
      endpoint: next.normalizedEndpoint,
      region: next.region.trim().isEmpty
          ? BackupS3State.defaultRegion
          : next.region.trim(),
      bucket: next.bucket.trim(),
      accessKeyId: next.accessKeyId.trim(),
      objectKey: next.normalizedObjectKey,
    );
    state = normalized;
    await Future.wait([
      GStorage.setting.put(_endpointKey, normalized.endpoint),
      GStorage.setting.put(_regionKey, normalized.region),
      GStorage.setting.put(_bucketKey, normalized.bucket),
      GStorage.setting.put(_accessKeyIdKey, normalized.accessKeyId),
      SecureCredentialVault.write(
        _secretAccessKeyKey,
        normalized.secretAccessKey,
      ),
      GStorage.setting.put(_objectKeyKey, normalized.objectKey),
      GStorage.setting.put(_usePathStyleKey, normalized.usePathStyle),
    ]);
  }

  void reload() {
    state = _load();
  }
}

final backupRemoteTypeProvider =
    StateNotifierProvider<BackupRemoteTypeNotifier, BackupRemoteType>((ref) {
      return BackupRemoteTypeNotifier();
    });

final backupWebDavProvider =
    StateNotifierProvider<BackupWebDavNotifier, BackupWebDavState>((ref) {
      return BackupWebDavNotifier();
    });

final backupS3Provider = StateNotifierProvider<BackupS3Notifier, BackupS3State>(
  (ref) {
    return BackupS3Notifier();
  },
);

webdav.Client createBackupWebDavClient(BackupWebDavState state) {
  final client = webdav.newClient(
    state.serverUrl.trim(),
    user: state.username.trim(),
    password: state.password,
  );
  client
    ..setConnectTimeout(10000)
    ..setReceiveTimeout(60000)
    ..setSendTimeout(60000);
  return client;
}
