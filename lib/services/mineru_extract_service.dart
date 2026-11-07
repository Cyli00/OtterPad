import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../data/models/ocr/doc_extract_config.dart';
import '../router/app_router.dart';
import 'batch_extract_service.dart';
import 'mineru_page_chunks.dart';
import 'mineru_result_converter.dart';
import 'mineru_parse_options.dart';
import 'pdf_process_lock.dart';

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
///   URL）。单次最多 200 页；更长的 PDF 用同一文件的多个 `page_ranges` 分片。
/// - 拿到 `{batch_id, file_urls[]}` 后按序 `PUT` 文件本体（不带 Content-Type）。
/// - `GET /api/v4/extract-results/batch/{batch_id}` 轮询。结果数组顺序不稳定，
///   必须按 `data_id` 收齐全部分片再按页序合并；取第一项或按完成顺序覆盖
///   同名 `full.md` 时，700 页文档会只留下约第 601 页以后的内容。
/// - 全部分片成功后才下载并合并，交给 [MinerUResultConverter] 落盘一次。
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

  /// 官方单次申请上传链接的文件数上限（含同一 PDF 的页码分片）。
  static const _maxFilesPerRequest = 200;
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
    _dio.httpClientAdapter = buildProxyAdapter(mode.name, host, port);
  }

  // ─── 请求体 ────────────────────────────────────────────────────────────

  /// 批量上传申请请求体（单个文件解析 / 批量文件解析共用此形状）。
  static Map<String, dynamic> buildUploadRequest(
    DocExtractApiState state,
    List<({String name, String dataId, String? pageRanges})> files,
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
          {
            'name': f.name,
            'is_ocr': state.mineruIsOcr,
            'data_id': f.dataId,
            if (f.pageRanges != null) 'page_ranges': f.pageRanges,
          },
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
    required List<({String name, String dataId, String? pageRanges})> files,
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

  Future<Uint8List> _downloadZipBytes(
    String zipUrl,
    CancelToken? cancelToken,
  ) async {
    _throwIfCancelled(cancelToken);
    try {
      final response = await _dio.get<List<int>>(
        zipUrl,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw MinerUExtractException(
          _l10n?.mineruErrDownloadFailed('empty') ?? '下载结果失败: empty',
        );
      }
      return Uint8List.fromList(data);
    } on MinerUExtractException {
      rethrow;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final detail = e.message ?? e.type.name;
      throw MinerUExtractException(
        _l10n?.mineruErrDownloadFailed(detail) ?? '下载结果失败: $detail',
      );
    }
  }

  Future<int?> _pdfPageCount(String filePath) async {
    try {
      return await PdfProcessLock.instance.run(() async {
        final doc = await PdfDocument.openFile(filePath);
        try {
          return doc.pages.length;
        } finally {
          doc.dispose();
        }
      });
    } catch (e) {
      log.d('[MinerU] 页数读取失败: $e');
      return null;
    }
  }

  Future<List<_Part>> _partsFor({
    required String documentId,
    required String filePath,
    required String title,
    int? pageCount,
  }) async {
    final pages = pageCount ?? await _pdfPageCount(filePath);
    final chunks = planMinerUPageChunks(
      pages,
      maxPages: DocExtractProvider.mineru.maxPagesPerFile,
    );
    final name = p.basename(filePath);
    log.d(
      '[MinerU] $documentId pages=$pages '
      'ranges=${chunks.map((c) => c.label).join(',')}',
    );
    return [
      for (final chunk in chunks)
        _Part(
          documentId: documentId,
          filePath: filePath,
          title: title,
          fileName: name,
          partCount: chunks.length,
          chunk: chunk,
          dataId: _fitDataId(
            chunks.length == 1 ? documentId : '${documentId}_c${chunk.index}',
          ),
        ),
    ];
  }

  String _fitDataId(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    if (cleaned.length <= 128) return cleaned;
    return cleaned.substring(cleaned.length - 128);
  }

  String _failureMessage(_Part part, String message) {
    if (part.partCount == 1) return message;
    final range = part.chunk.pageRanges ?? part.chunk.label;
    return _l10n?.mineruErrChunkFailed(range, message) ??
        '第 $range 页解析失败: $message';
  }

  /// 上传并等齐同一批 `data_id`。分片未到齐时不返回，失败的分片不会被
  /// 另外几片的 ZIP 顶替。
  Future<Map<String, _DocOutcome>> _resolveDocuments({
    required List<_Part> parts,
    required String apiKey,
    required DocExtractApiState state,
    CancelToken? cancelToken,
    void Function(_Part part, String phase)? onState,
  }) async {
    final bytes = <String, Uint8List>{};
    final errors = <String, String>{};
    final batches = <({String id, List<_Part> parts})>[];
    if (parts.isEmpty) return {};
    onState?.call(parts.first, 'request');

    for (var i = 0; i < parts.length; i += _maxFilesPerRequest) {
      _throwIfCancelled(cancelToken);
      final slice = parts.sublist(
        i,
        math.min(i + _maxFilesPerRequest, parts.length),
      );
      final String batchId;
      final List<String> urls;
      try {
        (batchId, urls) = await _requestUploadUrls(
          token: apiKey,
          state: state,
          files: [
            for (final part in slice)
              (
                name: part.fileName,
                dataId: part.dataId,
                pageRanges: part.chunk.pageRanges,
              ),
          ],
          cancelToken: cancelToken,
        );
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
        for (final part in slice) {
          errors[part.dataId] = '$e';
        }
        continue;
      }
      var uploaded = false;
      for (var j = 0; j < slice.length; j++) {
        _throwIfCancelled(cancelToken);
        final part = slice[j];
        try {
          if (!uploaded) {
            onState?.call(part, 'uploaded');
            uploaded = true;
          }
          await _uploadFile(
            uploadUrl: urls[j],
            filePath: part.filePath,
            cancelToken: cancelToken,
          );
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) rethrow;
          errors[part.dataId] = '$e';
        } catch (e) {
          errors[part.dataId] = '$e';
        }
      }
      batches.add((id: batchId, parts: slice));
    }

    bool settled(_Part part) =>
        bytes.containsKey(part.dataId) || errors.containsKey(part.dataId);

    var pollFailures = 0;
    while (parts.any((part) => !settled(part))) {
      if (batches.isEmpty) break;
      _throwIfCancelled(cancelToken);
      await Future.delayed(pollInterval);
      _throwIfCancelled(cancelToken);
      for (final batch in batches) {
        if (batch.parts.every(settled)) continue;
        try {
          final items = await _pollBatchResults(batch.id, apiKey, cancelToken);
          pollFailures = 0;
          final byId = {for (final part in batch.parts) part.dataId: part};
          for (final entry in items) {
            final dataId = entry['data_id'] as String?;
            final part = dataId == null ? null : byId[dataId];
            if (part == null || settled(part)) continue;
            final phase = entry['state'] as String? ?? '';
            if (phase.isNotEmpty) onState?.call(part, phase);
            switch (phase) {
              case 'done':
                final zipUrl = entry['full_zip_url'] as String?;
                if (zipUrl == null) {
                  errors[part.dataId] =
                      _l10n?.mineruErrMissingResultUrl ?? '任务完成但无结果链接';
                  break;
                }
                try {
                  bytes[part.dataId] = await _downloadZipBytes(
                    zipUrl,
                    cancelToken,
                  );
                } on DioException catch (e) {
                  if (e.type == DioExceptionType.cancel) rethrow;
                  errors[part.dataId] =
                      _l10n?.mineruErrDownloadFailed(
                        e.message ?? e.type.name,
                      ) ??
                      '下载结果失败: ${e.message ?? e.type.name}';
                } catch (e) {
                  errors[part.dataId] = '$e';
                }
              case 'failed':
                final msg = entry['err_msg'] as String?;
                errors[part.dataId] = msg != null && msg.isNotEmpty
                    ? msg
                    : (_l10n?.mineruErrTaskFailed ?? '解析失败');
            }
          }
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
          log.d('[MinerU] poll error: $e');
          final permanent = e is MinerUExtractException && !e.retryable;
          if (++pollFailures < 3 && !permanent) break;
          for (final part in parts) {
            if (!settled(part)) errors[part.dataId] = '$e';
          }
          break;
        }
      }
    }

    final outcomes = <String, _DocOutcome>{};
    final docIds = parts.map((part) => part.documentId).toSet();
    for (final id in docIds) {
      final docParts = parts.where((part) => part.documentId == id).toList()
        ..sort((a, b) => a.chunk.index.compareTo(b.chunk.index));
      final failed = docParts
          .where((part) => errors.containsKey(part.dataId))
          .toList();
      if (failed.isNotEmpty || docParts.any((part) => !settled(part))) {
        final part = failed.isNotEmpty ? failed.first : docParts.first;
        outcomes[id] = _DocOutcome(
          error: _failureMessage(
            part,
            errors[part.dataId] ?? (_l10n?.mineruErrTaskFailed ?? '解析失败'),
          ),
        );
        continue;
      }
      final pieces = [
        for (final part in docParts)
          (chunk: part.chunk, bytes: bytes[part.dataId]!),
      ];
      try {
        final merged = docParts.length == 1
            ? pieces.single.bytes
            : mergeMinerUResultZips(pieces);
        outcomes[id] = _DocOutcome(bytes: merged);
      } on FormatException catch (e) {
        outcomes[id] = _DocOutcome(error: e.message);
      }
    }
    return outcomes;
  }

  Future<File> _writeZip(String pdfPath, Uint8List bytes) async {
    final zip = File(p.join(p.dirname(pdfPath), 'extract.mineru.zip'));
    await zip.writeAsBytes(bytes, flush: true);
    return zip;
  }

  // ─── 单文档提取 ────────────────────────────────────────────────────────

  /// 单个文件解析。超过单次页数上限时按 `page_ranges` 拆开，齐了再合并成
  /// 一个 ZIP，由调用方交给 [MinerUResultConverter] 落盘。
  ///
  /// [pageCount] 已知时不再读 PDF。未知时本地计数；计数失败则整份上传，
  /// 由服务商按 200 页上限拒绝，而不是猜一个页段。
  Future<File> extractSingle({
    required String filePath,
    required String apiKey,
    required DocExtractApiState state,
    int? pageCount,
    void Function(String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final l = _l10n;
    final parts = await _partsFor(
      documentId: 'single',
      filePath: filePath,
      title: '',
      pageCount: pageCount,
    );
    final outcome = (await _resolveDocuments(
      parts: parts,
      apiKey: apiKey,
      state: state,
      cancelToken: cancelToken,
      onState: (part, phase) {
        onProgress?.call(switch (phase) {
          'request' => l?.mineruProgressRequestingUpload ?? '正在申请上传',
          'uploaded' => l?.mineruProgressUploading ?? '正在上传',
          'waiting-file' || 'pending' => l?.mineruProgressQueued ?? '排队中',
          'converting' => l?.mineruProgressConverting ?? '正在转换格式',
          'done' => l?.mineruProgressDownloading ?? '正在下载结果',
          _ => l?.mineruProgressParsing ?? '正在解析',
        });
      },
    ))['single']!;
    if (outcome.error != null) {
      throw MinerUExtractException(outcome.error!);
    }
    final data = outcome.bytes;
    if (data == null) {
      throw MinerUExtractException(l?.mineruErrTaskFailed ?? '解析失败');
    }
    return _writeZip(filePath, data);
  }

  // ─── 批量提取 ──────────────────────────────────────────────────────────

  /// 批量文件解析。超长 PDF 与单文档走同一套页段拆分；一篇文献的分片齐了
  /// 才转化一次。某一段失败时不把其它段写成这篇的阅读版。
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
    final byDoc = {for (final status in statuses) status.documentId: status};
    final results = <String, String?>{};
    final parts = <_Part>[];
    for (final item in items) {
      parts.addAll(
        await _partsFor(
          documentId: item.documentId,
          filePath: item.filePath,
          title: item.title,
          pageCount: null,
        ),
      );
    }
    log.d('[MinerU] batch start: ${items.length} files, ${parts.length} parts');

    void publish(BatchJobStatus status, [String? currentTitle]) {
      onJobUpdate?.call(status);
      onProgress?.call(
        BatchExtractProgress.fromStatuses(statuses, currentTitle ?? ''),
      );
    }

    final Map<String, _DocOutcome> resolved;
    try {
      resolved = await _resolveDocuments(
        parts: parts,
        apiKey: apiKey,
        state: state,
        cancelToken: cancelToken,
        onState: (part, phase) {
          final status = byDoc[part.documentId];
          if (status == null ||
              status.state == BatchJobState.done ||
              status.state == BatchJobState.failed ||
              status.state == BatchJobState.cancelled) {
            return;
          }
          status.state = phase == 'uploaded'
              ? BatchJobState.submitted
              : BatchJobState.running;
          publish(status, part.title);
        },
      );
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) rethrow;
      for (final status in statuses) {
        if (status.state == BatchJobState.pending ||
            status.state == BatchJobState.submitted ||
            status.state == BatchJobState.running) {
          status.state = BatchJobState.cancelled;
          results[status.documentId] = null;
          publish(status);
        }
      }
      return results;
    }

    for (final item in items) {
      if (cancelToken?.isCancelled == true) break;
      final status = byDoc[item.documentId]!;
      final outcome = resolved[item.documentId];
      if (outcome == null || outcome.error != null || outcome.bytes == null) {
        status.state = BatchJobState.failed;
        status.error = outcome?.error ?? (_l10n?.mineruErrTaskFailed ?? '解析失败');
        results[item.documentId] = null;
        publish(status, item.title);
        continue;
      }
      try {
        final zipFile = await _writeZip(item.filePath, outcome.bytes!);
        final converted = await MinerUResultConverter.instance.convert(
          pdfPath: item.filePath,
          zipFile: zipFile,
          title: item.title,
          cancelToken: cancelToken,
        );
        status.savedPath = converted.mdPath;
        status.totalPages = converted.pageCount;
        status.extractedPages = converted.pageCount;
        results[item.documentId] = converted.mdPath;
        status.state = BatchJobState.done;
      } catch (e) {
        if (cancelToken?.isCancelled == true) {
          status.state = BatchJobState.cancelled;
          results[item.documentId] = null;
          publish(status, item.title);
          break;
        }
        status.state = BatchJobState.failed;
        status.error = _l10n?.mineruErrSaveResultFailed('$e') ?? '保存结果失败: $e';
        results[item.documentId] = null;
      }
      publish(status, item.title);
    }

    if (cancelToken?.isCancelled == true) {
      for (final status in statuses) {
        if (status.state == BatchJobState.pending ||
            status.state == BatchJobState.submitted ||
            status.state == BatchJobState.running) {
          status.state = BatchJobState.cancelled;
          results[status.documentId] = null;
          publish(status);
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

class _Part {
  final String documentId;
  final String filePath;
  final String title;
  final String fileName;
  final String dataId;
  final MinerUPageChunk chunk;
  final int partCount;

  const _Part({
    required this.documentId,
    required this.filePath,
    required this.title,
    required this.fileName,
    required this.dataId,
    required this.chunk,
    required this.partCount,
  });
}

class _DocOutcome {
  final Uint8List? bytes;
  final String? error;
  const _DocOutcome({this.bytes, this.error});
}
