import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../providers/backup_provider.dart';
import 'proxy_adapter.dart';

/// ListObjectsV2 返回的单个对象信息。
class S3ObjectInfo {
  final String key;
  final int size;
  final DateTime? lastModified;

  const S3ObjectInfo({
    required this.key,
    required this.size,
    this.lastModified,
  });
}

class BackupS3Service {
  BackupS3Service._();

  static final instance = BackupS3Service._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(minutes: 3),
      receiveTimeout: const Duration(minutes: 3),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(mode.name, host, port);
  }

  Future<void> ping(BackupS3State config) async {
    final response = await _signedRequest(
      config,
      method: 'HEAD',
      objectKey: null,
      responseType: ResponseType.plain,
    );
    if (response.statusCode != 200) {
      throw Exception(_formatResponseError(response));
    }
  }

  /// [objectKey] 缺省用配置里的固定 key；版本化备份由调用方传时间戳 key。
  Future<void> uploadFile(
    BackupS3State config,
    String localPath, {
    String? objectKey,
  }) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final response = await _signedRequest(
      config,
      method: 'PUT',
      objectKey: objectKey ?? config.normalizedObjectKey,
      bodyBytes: bytes,
      responseType: ResponseType.plain,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_formatResponseError(response));
    }
  }

  Future<void> downloadFile(
    BackupS3State config,
    String savePath, {
    String? objectKey,
  }) async {
    final response = await _signedRequest(
      config,
      method: 'GET',
      objectKey: objectKey ?? config.normalizedObjectKey,
      responseType: ResponseType.bytes,
    );
    if (response.statusCode != 200) {
      throw Exception(_formatResponseError(response));
    }

    final data = response.data;
    final bytes = switch (data) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => throw Exception('S3 返回了无法识别的文件内容'),
    };

    await Directory(p.dirname(savePath)).create(recursive: true);
    await File(savePath).writeAsBytes(bytes, flush: true);
  }

  /// 列出 [prefix] 下的对象（ListObjectsV2）。备份目录最多几十个文件，
  /// 不做分页（MaxKeys 默认 1000 远够）。
  Future<List<S3ObjectInfo>> listObjects(
    BackupS3State config,
    String prefix,
  ) async {
    final response = await _signedRequest(
      config,
      method: 'GET',
      objectKey: null,
      responseType: ResponseType.plain,
      queryParameters: {
        'list-type': '2',
        if (prefix.isNotEmpty) 'prefix': prefix,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(_formatResponseError(response));
    }
    return _parseListObjects(response.data?.toString() ?? '');
  }

  Future<void> deleteObject(BackupS3State config, String objectKey) async {
    final response = await _signedRequest(
      config,
      method: 'DELETE',
      objectKey: objectKey,
      responseType: ResponseType.plain,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_formatResponseError(response));
    }
  }

  /// 解析 ListObjectsV2 XML。结构固定且字段无嵌套歧义（Contents 内
  /// Key/Size/LastModified 各一），正则提取足够，不为此引入 xml 包。
  static List<S3ObjectInfo> _parseListObjects(String xml) {
    final contents = RegExp(
      r'<Contents>(.*?)</Contents>',
      dotAll: true,
    ).allMatches(xml);
    final result = <S3ObjectInfo>[];
    for (final m in contents) {
      final block = m.group(1)!;
      String? field(String tag) => RegExp(
        '<$tag>(.*?)</$tag>',
        dotAll: true,
      ).firstMatch(block)?.group(1);
      final key = field('Key');
      if (key == null || key.isEmpty) continue;
      result.add(
        S3ObjectInfo(
          key: _unescapeXml(key),
          size: int.tryParse(field('Size') ?? '') ?? 0,
          lastModified: DateTime.tryParse(field('LastModified') ?? ''),
        ),
      );
    }
    return result;
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  Future<Response<dynamic>> _signedRequest(
    BackupS3State config, {
    required String method,
    required String? objectKey,
    required ResponseType responseType,
    Uint8List? bodyBytes,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildRequestUri(
      config,
      objectKey: objectKey,
      queryParameters: queryParameters,
    );
    final payload = bodyBytes ?? Uint8List(0);
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = _dateStamp(now);
    final payloadHash = _sha256Hex(payload);
    final host = _hostHeader(uri);

    final canonicalHeaders = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    final signedHeaders = canonicalHeaders.keys.toList()..sort();
    final canonicalHeaderText = signedHeaders
        .map((key) => '$key:${canonicalHeaders[key]!.trim()}')
        .join('\n');
    final credentialScope =
        '$dateStamp/${config.region.trim()}/s3/aws4_request';
    final canonicalRequest = [
      method,
      _canonicalUri(uri),
      _canonicalQuery(uri),
      '$canonicalHeaderText\n',
      signedHeaders.join(';'),
      payloadHash,
    ].join('\n');
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      _sha256Hex(utf8.encode(canonicalRequest)),
    ].join('\n');
    final signature = _signature(
      config.secretAccessKey,
      dateStamp,
      config.region.trim(),
      stringToSign,
    );
    final authorization =
        'AWS4-HMAC-SHA256 Credential=${config.accessKeyId.trim()}/$credentialScope, '
        'SignedHeaders=${signedHeaders.join(';')}, Signature=$signature';

    return _dio.requestUri(
      uri,
      data: method == 'PUT' ? payload : null,
      options: Options(
        method: method,
        responseType: responseType,
        headers: {
          'Authorization': authorization,
          'Host': host,
          'x-amz-content-sha256': payloadHash,
          'x-amz-date': amzDate,
        },
      ),
    );
  }

  Uri _buildRequestUri(
    BackupS3State config, {
    required String? objectKey,
    Map<String, String>? queryParameters,
  }) {
    final endpoint = Uri.parse(config.normalizedEndpoint);
    final baseSegments = endpoint.pathSegments.where((item) => item.isNotEmpty);
    final objectSegments = objectKey == null
        ? const <String>[]
        : objectKey.split('/').where((item) => item.isNotEmpty);
    final query = (queryParameters?.isEmpty ?? true) ? null : queryParameters;

    if (config.usePathStyle) {
      return Uri(
        scheme: endpoint.scheme,
        host: endpoint.host,
        port: endpoint.hasPort ? endpoint.port : null,
        pathSegments: [
          ...baseSegments,
          config.bucket.trim(),
          ...objectSegments,
        ],
        queryParameters: query,
      );
    }

    return Uri(
      scheme: endpoint.scheme,
      host: '${config.bucket.trim()}.${endpoint.host}',
      port: endpoint.hasPort ? endpoint.port : null,
      pathSegments: [...baseSegments, ...objectSegments],
      queryParameters: query,
    );
  }

  String _canonicalUri(Uri uri) {
    if (uri.path.isEmpty) return '/';
    return uri.pathSegments.isEmpty
        ? '/'
        : '/${uri.pathSegments.map(Uri.encodeComponent).join('/')}';
  }

  String _canonicalQuery(Uri uri) {
    if (uri.queryParametersAll.isEmpty) return '';
    final items = <String>[];
    final keys = uri.queryParametersAll.keys.toList()..sort();
    for (final key in keys) {
      final values = uri.queryParametersAll[key]!..sort();
      for (final value in values) {
        items.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    return items.join('&');
  }

  String _hostHeader(Uri uri) {
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    if (!uri.hasPort || uri.port == defaultPort) {
      return uri.host;
    }
    return '${uri.host}:${uri.port}';
  }

  String _amzDate(DateTime time) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        'T${two(time.hour)}${two(time.minute)}${two(time.second)}Z';
  }

  String _dateStamp(DateTime time) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}';
  }

  String _sha256Hex(List<int> value) {
    return sha256.convert(value).toString();
  }

  String _signature(
    String secretAccessKey,
    String dateStamp,
    String region,
    String stringToSign,
  ) {
    final keyDate = _hmacSha256(
      utf8.encode('AWS4$secretAccessKey'),
      utf8.encode(dateStamp),
    );
    final keyRegion = _hmacSha256(keyDate, utf8.encode(region));
    final keyService = _hmacSha256(keyRegion, utf8.encode('s3'));
    final keySigning = _hmacSha256(keyService, utf8.encode('aws4_request'));
    return Hmac(
      sha256,
      keySigning,
    ).convert(utf8.encode(stringToSign)).toString();
  }

  List<int> _hmacSha256(List<int> key, List<int> value) {
    return Hmac(sha256, key).convert(value).bytes;
  }

  String _formatResponseError(Response<dynamic> response) {
    final statusCode = response.statusCode ?? 0;
    final data = response.data;
    if (data is List<int>) {
      final text = utf8.decode(data, allowMalformed: true).trim();
      return 'S3 请求失败（$statusCode）：${text.isEmpty ? '无返回内容' : text}';
    }
    final text = data?.toString().trim() ?? '';
    return 'S3 请求失败（$statusCode）：${text.isEmpty ? '无返回内容' : text}';
  }
}
