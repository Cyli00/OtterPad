import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../providers/backup_provider.dart';
import 'backup_s3_service.dart';

/// 远端备份目录里的一个文件。[name] 是纯文件名（不含目录前缀）。
class BackupRemoteEntry {
  final String name;
  final int size;
  final DateTime? modified;

  const BackupRemoteEntry({
    required this.name,
    required this.size,
    this.modified,
  });
}

/// 远端备份存储的唯一接缝——S3 与 WebDAV 的协议细节（SigV4 签名 /
/// PROPFIND / 目录创建）止步于各自 adapter，调用方（设置页 / 备份编排 /
/// 自动备份）只依赖这 5 个动词。
///
/// 语义约定：每个实例绑定配置中的**远端目录**（S3 = objectKey 的目录
/// 部分，WebDAV = remoteDir），方法只接受目录内的文件名；[fixedName]
/// 是配置里的固定备份文件名（兼容既有单文件覆盖式备份）。
abstract class BackupRemote {
  /// 配置里的固定备份文件名（如 `otter_pad_backup.zip`）。
  String get fixedName;

  /// UI 展示用的目标描述（bucket/key 或 host+目录）。
  String get targetLabel;

  Future<void> ping();
  Future<void> upload(String localPath, String remoteName);
  Future<void> download(String remoteName, String savePath);
  Future<List<BackupRemoteEntry>> list();
  Future<void> delete(String remoteName);
}

/// 按当前配置解析 adapter；未配置返回 null。
BackupRemote? resolveBackupRemote(
  BackupRemoteType type,
  BackupS3State s3,
  BackupWebDavState webDav,
) => switch (type) {
  BackupRemoteType.s3 => s3.isConfigured ? _S3BackupRemote(s3) : null,
  BackupRemoteType.webdav =>
    webDav.isConfigured ? _WebDavBackupRemote(webDav) : null,
};

class _S3BackupRemote implements BackupRemote {
  final BackupS3State _config;

  /// objectKey 的目录部分作为远端目录前缀；key 在根目录时为空串。
  final String _prefix;

  _S3BackupRemote(this._config)
    : _prefix = p.posix.dirname(_config.normalizedObjectKey) == '.'
          ? ''
          : '${p.posix.dirname(_config.normalizedObjectKey)}/';

  @override
  String get fixedName => p.posix.basename(_config.normalizedObjectKey);

  @override
  String get targetLabel => '${_config.bucket.trim()}/$_prefix';

  String _keyOf(String name) => '$_prefix$name';

  @override
  Future<void> ping() => BackupS3Service.instance.ping(_config);

  @override
  Future<void> upload(String localPath, String remoteName) => BackupS3Service
      .instance
      .uploadFile(_config, localPath, objectKey: _keyOf(remoteName));

  @override
  Future<void> download(String remoteName, String savePath) => BackupS3Service
      .instance
      .downloadFile(_config, savePath, objectKey: _keyOf(remoteName));

  @override
  Future<List<BackupRemoteEntry>> list() async {
    final objects = await BackupS3Service.instance.listObjects(
      _config,
      _prefix,
    );
    return [
      for (final o in objects)
        // 过滤子目录对象：只认目录直下的文件
        if (!o.key.substring(_prefix.length).contains('/'))
          BackupRemoteEntry(
            name: o.key.substring(_prefix.length),
            size: o.size,
            modified: o.lastModified,
          ),
    ];
  }

  @override
  Future<void> delete(String remoteName) =>
      BackupS3Service.instance.deleteObject(_config, _keyOf(remoteName));
}

class _WebDavBackupRemote implements BackupRemote {
  final BackupWebDavState _config;

  _WebDavBackupRemote(this._config);

  webdav.Client get _client => createBackupWebDavClient(_config);

  String _pathOf(String name) =>
      '${BackupWebDavState.normalizeRemoteDir(_config.remoteDir)}/$name';

  @override
  String get fixedName => _config.fileName.trim().isEmpty
      ? BackupWebDavState.defaultFileName
      : _config.fileName.trim();

  @override
  String get targetLabel =>
      '${Uri.tryParse(_config.serverUrl.trim())?.host ?? _config.serverUrl}'
      '${BackupWebDavState.normalizeRemoteDir(_config.remoteDir)}';

  @override
  Future<void> ping() => _client.ping();

  @override
  Future<void> upload(String localPath, String remoteName) async {
    final client = _client;
    await client.mkdirAll(
      BackupWebDavState.normalizeRemoteDir(_config.remoteDir),
    );
    await client.writeFromFile(localPath, _pathOf(remoteName));
  }

  @override
  Future<void> download(String remoteName, String savePath) =>
      _client.read2File(_pathOf(remoteName), savePath);

  @override
  Future<List<BackupRemoteEntry>> list() async {
    final files = await _client.readDir(
      BackupWebDavState.normalizeRemoteDir(_config.remoteDir),
    );
    return [
      for (final f in files)
        if (f.isDir != true && (f.name ?? '').isNotEmpty)
          BackupRemoteEntry(
            name: f.name!,
            size: f.size ?? 0,
            modified: f.mTime,
          ),
    ];
  }

  @override
  Future<void> delete(String remoteName) => _client.remove(_pathOf(remoteName));
}
