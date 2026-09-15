import 'dart:io';

import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../data/models/ocr/doc_extract_config.dart';
import '../router/app_router.dart';
import 'batch_extract_service.dart';
import 'mineru_result_converter.dart';
import 'mineru_parse_options.dart';

/// MinerU 精准解析 API 异常
class MinerUExtractException implements Exception {
  final String message;
  final bool retryable;
  const MinerUExtractException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

/// MinerU 精准解析 API（v4）服务。
///
/// **唯一接缝**：MinerU 请求体构造、签名 URL 上传、批量结果轮询全在这里。
///
/// 端点约束（https://mineru.net/apiManage/docs）：
/// - 本地文件解析一律 `POST /api/v4/file-urls/batch`（`/extract/task` 只吃公网
///   URL）；单文件 = files 数组长度 1。
/// - 拿到 `{batch_id, file_urls[]}` 后按序 `PUT` 文件本体（不带 Content-Type）。
/// - `GET /api/v4/extract-results/batch/{batch_id}` 轮询，按 `data_id`
///   (= documentId) 关联结果（本地 PDF 统一叫 source.pdf，文件名不可靠）。
/// - `state=done` 时下载 `full_zip_url`，交给 [MinerUResultConverter] 落盘。
///
/// 固定使用 VLM 解析（Pipeline 尚未接入）。
class MinerUExtractService {
  MinerUExtractService({
    Dio? client,
    this.pollInterval = const Duration(seconds: 5),
  }) : _dio =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 600),
             ),
           );
  static final MinerUExtractService instance = MinerUExtractService();
  static const _baseUrl = 'https://mineru.net/api/v4';
  final Duration pollInterval;
  final Dio _dio;

  /// 服务层拿不到 BuildContext，按项目约定经 `rootNavigatorKey` 取 l10n；
  /// 取不到时（启动早期 / 测试）回落中文兜底串。
  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  // ─── 代理 ──────────────────────────────────────────────────────────────

  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(
      mode.name,
      host,
      port,
    );
  }

  // ─── 请求体 ────────────────────────────────────────────────────────────

  /// 批量上传申请请求体（单个文件解析 / 批量文件解析共用此形状）。
  static Map<String, dynamic> buildUploadRequest(
    DocExtractApiState state,
    List<({String name, String dataId})> files,
  ) {
    if (!MinerUParseOptions.languages.contains(state.mineruLanguage) ||
        state.mineruExtraFormats.any(
          (f) => !MinerUParseOptions.extraFormats.contains(f),
        )) {
      throw ArgumentError('MinerU 解析参数无效');
    }
    return {
      'enable_formula': state.mineruEnableFormula,
      'enable_table': state.mineruEnableTable,
      'language': state.mineruLanguage,
      // 当前只接入 VLM，不随状态或旧设置变化。
      'model_version': MinerUParseOptions.onlyModel,
      if (state.mineruExtraFormats.isNotEmpty)
        'extra_formats': state.mineruExtraFormats.toSet().toList(),
      'files': [
        for (final f in files)
          {'name': f.name, 'is_ocr': state.mineruIsOcr, 'data_id': f.dataId},
      ],
    };
  }

  // ─── 错误映射 ──────────────────────────────────────────────────────────

  /// 业务错误码 → 友好描述。未知码回落原始 msg。
  String _describeErrorCode(Object? code, String msg) {
    final l = _l10n;
    return switch (code) {
      -500 ||
      -10001 ||
      -10002 => l?.mineruErrInvalidParams(msg) ?? '参数错误: $msg',
      -60002 => l?.mineruErrUnsupportedFormat ?? '不支持的文件格式',
      -60003 || -60004 => l?.mineruErrFileUnreadable ?? '文件读取失败或为空',
      -60005 => l?.mineruErrFileTooLarge ?? '文件超过 200MB 大小限制',
      -60006 => l?.mineruErrTooManyPages ?? '页数超过单文件 200 页限制',
      -60008 => l?.mineruErrFileTimeout ?? '文件读取超时',
      -60010 => l?.mineruErrParseFailed ?? '文档解析失败',
      -60015 || -60016 => l?.mineruErrConvertFailed ?? '文件 / 格式转换失败',
      -60018 => l?.mineruErrQuotaExhausted ?? '今日解析额度已用尽，请明日再试',
      _ =>
        msg.isNotEmpty ? msg : (l?.mineruErrUnknown('$code') ?? '未知错误 ($code)'),
    };
  }

  /// 检查响应体：业务层 `{code, msg}` 与网关层 `{success:false, msgCode}` 两种形状。
  void _checkResponse(Map<String, dynamic>? body) {
    final l = _l10n;
    if (body == null) return;
    // 网关/鉴权层失败形状
    if (body['success'] == false) {
      final msgCode = body['msgCode'] as String? ?? '';
      final msg = body['msg'] as String? ?? '';
      throw MinerUExtractException(switch (msgCode) {
        'A0202' => l?.mineruErrTokenInvalid ?? 'API Token 无效（A0202）',
        'A0211' => l?.mineruErrTokenExpired ?? 'API Token 已过期（A0211）',
        _ =>
          l?.mineruErrRequestRejected(msgCode, msg) ?? '请求被拒绝 ($msgCode): $msg',
      });
    }
    final code = body['code'];
    if (code == null || code == 0) return;
    final msg = body['msg'] as String? ?? '';
    throw MinerUExtractException(_describeErrorCode(code, msg));
  }

  static Map<String, dynamic>? _safeMap(Object? data) =>
      data is Map<String, dynamic> ? data : null;

  // ─── 内部步骤 ──────────────────────────────────────────────────────────

  /// 申请上传 URL，返回 (batchId, 每个文件对应的签名上传 URL)。
  Future<(String, List<String>)> _requestUploadUrls({
    required String token,
    required DocExtractApiState state,
    required List<({String name, String dataId})> files,
    CancelToken? cancelToken,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/file-urls/batch',
        data: buildUploadRequest(state, files),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      _checkResponse(_safeMap(e.response?.data));
      final detail = e.message ?? e.type.name;
      throw MinerUExtractException(
        _l10n?.mineruErrRequestUploadFailed(detail) ?? '申请上传失败: $detail',
      );
    }
    _checkResponse(response.data);
    final data = response.data?['data'] as Map<String, dynamic>?;
    final batchId = data?['batch_id'] as String?;
    final urls =
        (data?['file_urls'] as List?)?.whereType<String>().toList() ?? [];
    if (batchId == null || urls.length != files.length) {
      throw MinerUExtractException(
        _l10n?.mineruErrMissingFileUrls ?? '申请上传响应缺少 batch_id / file_urls',
      );
    }
    return (batchId, urls);
  }

  /// PUT 文件本体到签名 URL（不带 Content-Type 头）。
  Future<void> _uploadFile({
    required String uploadUrl,
    required String filePath,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.put<void>(
        uploadUrl,
        data: File(filePath).openRead(),
        options: Options(
          headers: {Headers.contentLengthHeader: await File(filePath).length()},
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final name = p.basename(filePath);
      final detail = e.message ?? e.type.name;
      throw MinerUExtractException(
        _l10n?.mineruErrUploadFailed(name, detail) ?? '上传文件失败 ($name): $detail',
      );
    }
  }

  /// 轮询批量结果一次，返回 extract_result 条目数组。
  Future<List<Map<String, dynamic>>> _pollBatchResults(
    String batchId,
    String token,
    CancelToken? cancelToken,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/extract-results/batch/$batchId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      _checkResponse(_safeMap(e.response?.data));
      final detail = e.message ?? e.type.name;
      throw MinerUExtractException(
        _l10n?.mineruErrPollFailed(detail) ?? '查询结果失败: $detail',
        retryable:
            e.response?.statusCode != 401 && e.response?.statusCode != 403,
      );
    }
    _checkResponse(response.data);
    final list = response.data?['data']?['extract_result'] as List?;
    return list?.whereType<Map<String, dynamic>>().toList() ?? [];
  }

  /// 下载 zip 到文献目录（临时文件，converter 消费后删除）。
  Future<File> _downloadZip(
    String zipUrl,
    String pdfPath,
    CancelToken? cancelToken,
  ) async {
    _throwIfCancelled(cancelToken);
    final zipPath = p.join(p.dirname(pdfPath), 'extract.mineru.zip');
    try {
      await _dio.download(zipUrl, zipPath, cancelToken: cancelToken);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final detail = e.message ?? e.type.name;
      throw MinerUExtractException(
        _l10n?.mineruErrDownloadFailed(detail) ?? '下载结果失败: $detail',
      );
    }
    return File(zipPath);
  }

  // ─── 单文档提取 ────────────────────────────────────────────────────────

  /// 单个文件解析（「文档提取」按钮）：借批量通道（files 长度 1）。
  /// 返回下载好的 zip 文件，由调用方交给 [MinerUResultConverter] 落盘。
  Future<File> extractSingle({
    required String filePath,
    required String apiKey,
    required DocExtractApiState state,
    void Function(String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final l = _l10n;
    onProgress?.call(l?.mineruProgressRequestingUpload ?? '正在申请上传…');
    final (batchId, urls) = await _requestUploadUrls(
      token: apiKey,
      state: state,
      files: [(name: p.basename(filePath), dataId: 'single')],
      cancelToken: cancelToken,
    );

    onProgress?.call(l?.mineruProgressUploading ?? '正在上传…');
    await _uploadFile(
      uploadUrl: urls.single,
      filePath: filePath,
      cancelToken: cancelToken,
    );

    while (true) {
      _throwIfCancelled(cancelToken);
      await Future.delayed(pollInterval);
      _throwIfCancelled(cancelToken);
      final items = await _pollBatchResults(batchId, apiKey, cancelToken);
      _throwIfCancelled(cancelToken);
      if (items.isEmpty) continue;
      final item = items.first;
      switch (item['state'] as String? ?? '') {
        case 'waiting-file' || 'pending':
          onProgress?.call(l?.mineruProgressQueued ?? '排队中…');
        case 'running':
          onProgress?.call(l?.mineruProgressParsing ?? '正在解析…');
        case 'converting':
          onProgress?.call(l?.mineruProgressConverting ?? '正在转换格式…');
        case 'done':
          final zipUrl = item['full_zip_url'] as String?;
          if (zipUrl == null) {
            throw MinerUExtractException(
              l?.mineruErrMissingResultUrl ?? '任务完成但无结果链接',
            );
          }
          onProgress?.call(l?.mineruProgressDownloading ?? '正在下载结果…');
          return _downloadZip(zipUrl, filePath, cancelToken);
        case 'failed':
          throw MinerUExtractException(
            (item['err_msg'] as String?)?.isNotEmpty == true
                ? item['err_msg'] as String
                : (l?.mineruErrTaskFailed ?? '解析失败'),
          );
      }
    }
  }

  // ─── 批量提取 ──────────────────────────────────────────────────────────

  /// 批量文件解析（多选文献卡片的「文档提取」）：一次批量申请 + 逐个 PUT +
  /// 批量轮询，完成一个转化一个。返回 documentId → 阅读版 markdown 路径。
  Future<BatchExtractResults> extractBatch({
    required List<BatchExtractItem> items,
    required String apiKey,
    required DocExtractApiState state,
    void Function(BatchExtractProgress)? onProgress,
    void Function(BatchJobStatus)? onJobUpdate,
    CancelToken? cancelToken,
  }) async {
    final statuses = [
      for (final item in items)
        BatchJobStatus(documentId: item.documentId, title: item.title),
    ];
    final results = <String, String?>{};

    // Phase 1: 申请批量上传 URL
    log.d('[MinerU] batch start: ${items.length} files');
    late final String batchId;
    late final List<String> urls;
    try {
      (batchId, urls) = await _requestUploadUrls(
        token: apiKey,
        state: state,
        files: [
          for (final item in items)
            (name: p.basename(item.filePath), dataId: item.documentId),
        ],
        cancelToken: cancelToken,
      );
    } catch (e) {
      // 申请失败 → 全部失败
      for (final s in statuses) {
        s.state = BatchJobState.failed;
        s.error = e.toString();
        results[s.documentId] = null;
        onJobUpdate?.call(s);
      }
      rethrow;
    }

    // Phase 2: 逐个上传（串行，避免大文件并发占满带宽）
    for (var i = 0; i < items.length; i++) {
      if (cancelToken?.isCancelled == true) break;
      final status = statuses[i];
      try {
        await _uploadFile(
          uploadUrl: urls[i],
          filePath: items[i].filePath,
          cancelToken: cancelToken,
        );
        status.state = BatchJobState.submitted;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          status.state = BatchJobState.cancelled;
        } else {
          status.state = BatchJobState.failed;
          status.error = e.toString();
        }
        results[status.documentId] = null;
      } catch (e) {
        status.state = BatchJobState.failed;
        status.error = e.toString();
        results[status.documentId] = null;
      }
      onJobUpdate?.call(status);
      onProgress?.call(
        BatchExtractProgress.fromStatuses(statuses, items[i].title),
      );
    }

    // Phase 3: 批量轮询，完成一个落盘一个
    final byDataId = {for (final s in statuses) s.documentId: s};
    final dataIdToItem = {for (final item in items) item.documentId: item};

    var pollFailures = 0;
    while (cancelToken?.isCancelled != true) {
      final active = statuses
          .where(
            (s) =>
                s.state == BatchJobState.submitted ||
                s.state == BatchJobState.running,
          )
          .length;
      if (active == 0) break;

      await Future.delayed(pollInterval);
      if (cancelToken?.isCancelled == true) break;
      final List<Map<String, dynamic>> extractResult;
      try {
        extractResult = await _pollBatchResults(batchId, apiKey, cancelToken);
        pollFailures = 0;
      } catch (e) {
        if (cancelToken?.isCancelled == true) break;
        log.d('[MinerU] poll error: $e');
        final permanent = e is MinerUExtractException && !e.retryable;
        if (++pollFailures < 3 && !permanent) continue;
        for (final status in statuses.where(
          (s) =>
              s.state == BatchJobState.submitted ||
              s.state == BatchJobState.running,
        )) {
          status.state = BatchJobState.failed;
          status.error = e.toString();
          results[status.documentId] = null;
          onJobUpdate?.call(status);
        }
        break;
      }

      for (final entry in extractResult) {
        if (cancelToken?.isCancelled == true) break;
        final dataId = entry['data_id'] as String?;
        final status = dataId != null ? byDataId[dataId] : null;
        if (status == null ||
            (status.state != BatchJobState.submitted &&
                status.state != BatchJobState.running)) {
          continue;
        }
        switch (entry['state'] as String? ?? '') {
          case 'waiting-file' || 'pending' || 'running' || 'converting':
            status.state = BatchJobState.running;
          case 'done':
            final zipUrl = entry['full_zip_url'] as String?;
            final item = dataIdToItem[dataId];
            if (zipUrl == null || item == null) {
              status.state = BatchJobState.failed;
              status.error = _l10n?.mineruErrMissingResultUrl ?? '任务完成但无结果链接';
              results[status.documentId] = null;
              break;
            }
            try {
              final zipFile = await _downloadZip(
                zipUrl,
                item.filePath,
                cancelToken,
              );
              final converted = await MinerUResultConverter.instance.convert(
                pdfPath: item.filePath,
                zipFile: zipFile,
                title: item.title,
                cancelToken: cancelToken,
              );
              status.savedPath = converted.mdPath;
              status.totalPages = converted.pageCount;
              status.extractedPages = converted.pageCount;
              results[status.documentId] = converted.mdPath;
              status.state = BatchJobState.done;
            } catch (e) {
              if (cancelToken?.isCancelled == true) break;
              status.state = BatchJobState.failed;
              status.error =
                  _l10n?.mineruErrSaveResultFailed('$e') ?? '保存结果失败: $e';
              results[status.documentId] = null;
            }
          case 'failed':
            status.state = BatchJobState.failed;
            status.error = (entry['err_msg'] as String?)?.isNotEmpty == true
                ? entry['err_msg'] as String
                : (_l10n?.mineruErrTaskFailed ?? '解析失败');
            results[status.documentId] = null;
        }
        onJobUpdate?.call(status);
      }
      onProgress?.call(BatchExtractProgress.fromStatuses(statuses, ''));
    }

    if (cancelToken?.isCancelled == true) {
      for (final status in statuses) {
        if (status.state == BatchJobState.pending ||
            status.state == BatchJobState.submitted ||
            status.state == BatchJobState.running) {
          status.state = BatchJobState.cancelled;
          results[status.documentId] = null;
          onJobUpdate?.call(status);
        }
      }
    }

    return results;
  }

  void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    }
  }
}
