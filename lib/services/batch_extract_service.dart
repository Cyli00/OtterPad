import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';
import 'doc_extract_service.dart';

// ─── 数据模型 ─────────────────────────────────────────────────────────────────

/// 批量提取单项输入，[documentId] 与 [filePath] 一一对应。
class BatchExtractItem {
  final String documentId;
  final String filePath;
  final String title;

  const BatchExtractItem({
    required this.documentId,
    required this.filePath,
    required this.title,
  });
}

enum BatchJobState { pending, submitted, running, done, failed, cancelled }

/// 单个 Job 的运行时状态（可变对象，由 [BatchExtractService] 内部维护）。
class BatchJobStatus {
  final String documentId;
  final String title;
  BatchJobState state;
  String? jobId;
  String? error;
  int extractedPages;
  int totalPages;
  String? savedPath;

  BatchJobStatus({
    required this.documentId,
    required this.title,
    this.state = BatchJobState.pending,
    this.jobId,
    this.error,
    this.extractedPages = 0,
    this.totalPages = 0,
    this.savedPath,
  });
}

/// 批量提取整体进度快照（不可变，每次回调时生成新实例）。
class BatchExtractProgress {
  final int total;
  final int completed;
  final int succeeded;
  final int failed;
  final String currentTitle;
  final List<BatchJobStatus> statuses;

  const BatchExtractProgress({
    required this.total,
    required this.completed,
    required this.succeeded,
    required this.failed,
    required this.currentTitle,
    required this.statuses,
  });
}

/// documentId → 已保存的 HTML 路径（null 表示该文献提取失败）
typedef BatchExtractResults = Map<String, String?>;

class BatchExtractException implements Exception {
  final String message;
  const BatchExtractException(this.message);
  @override
  String toString() => message;
}

// ─── 服务 ─────────────────────────────────────────────────────────────────────

/// 百度 AI Studio PaddleOCR-VL 批量异步提取服务。
///
/// 使用 v2 Job API（与同步 layout-parsing 不同）：
///   1. 以 multipart/form-data 上传 PDF，获取 jobId
///   2. 轮询 job 状态（每 5 秒一轮）
///   3. job 完成后下载 JSONL，解析并复用 [DocExtractService.saveResult] 保存结果
///
/// 提取结果通过 [BatchExtractItem.documentId] 与文献条目一一对应。
class BatchExtractService {
  BatchExtractService._();
  static final BatchExtractService instance = BatchExtractService._();

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 300),
    sendTimeout: const Duration(seconds: 120),
  ));

  // ─── 代理配置 ──────────────────────────────────────────────────────────────

  void applyProxy(Enum mode, String host, int port) {
    final adapter = IOHttpClientAdapter();
    switch (mode.name) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      case 'system':
        adapter.createHttpClient = () => HttpClient();
      default:
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          return client;
        };
    }
    _dio.httpClientAdapter = adapter;
  }

  // ─── 内部工具 ──────────────────────────────────────────────────────────────

  String _jobUrl(String apiBaseUrl) {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/api/v2/ocr/jobs';
  }

  Map<String, dynamic> _buildOptionalPayload(DocExtractApiState state) {
    return {
      'useLayoutDetection': state.useLayoutDetection,
      'useChartRecognition': state.useChartRecognition,
      'useDocOrientationClassify': state.useDocOrientationClassify,
      'useDocUnwarping': state.useDocUnwarping,
      'useSealRecognition': state.useSealRecognition,
      'useOcrForImageBlock': state.useOcrForImageBlock,
      'mergeTables': state.mergeTables,
      'relevelTitles': state.relevelTitles,
      'restructurePages': state.restructurePages,
      'layoutNms': state.layoutNms,
      if (state.markdownIgnoreLabels.isNotEmpty)
        'markdownIgnoreLabels': state.markdownIgnoreLabels,
    };
  }

  BatchExtractProgress _buildProgress(
    List<BatchJobStatus> statuses,
    String currentTitle,
  ) {
    final succeeded =
        statuses.where((s) => s.state == BatchJobState.done).length;
    final failed = statuses
        .where((s) =>
            s.state == BatchJobState.failed ||
            s.state == BatchJobState.cancelled)
        .length;
    return BatchExtractProgress(
      total: statuses.length,
      completed: succeeded + failed,
      succeeded: succeeded,
      failed: failed,
      currentTitle: currentTitle,
      // 拷贝一份快照，避免后续修改影响已派发的回调数据
      statuses: statuses
          .map((s) => BatchJobStatus(
                documentId: s.documentId,
                title: s.title,
                state: s.state,
                jobId: s.jobId,
                error: s.error,
                extractedPages: s.extractedPages,
                totalPages: s.totalPages,
                savedPath: s.savedPath,
              ))
          .toList(),
    );
  }

  // ─── Job 提交与轮询 ────────────────────────────────────────────────────────

  /// 以 multipart/form-data 提交提取任务，返回 jobId。
  ///
  /// v2 API 使用 `bearer` 授权头（小写），且文件以原始字节上传而非 base64。
  Future<String> _submitJob({
    required String filePath,
    required String jobUrl,
    required String token,
    required DocExtractApiState state,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: p.basename(filePath)),
      'model': 'PaddleOCR-VL-1.5',
      'optionalPayload': jsonEncode(_buildOptionalPayload(state)),
    });

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        jobUrl,
        data: formData,
        options: Options(headers: {'Authorization': 'bearer $token'}),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw BatchExtractException('提交任务失败: ${e.message ?? e.type.name}');
    }

    final jobId = response.data?['data']?['jobId'] as String?;
    if (jobId == null) {
      throw const BatchExtractException('提交任务失败: 响应中无 jobId');
    }
    return jobId;
  }

  /// 查询单个 Job 的当前状态数据。
  Future<Map<String, dynamic>> _pollOnce(
    String jobId,
    String jobUrl,
    String token,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(
        '$jobUrl/$jobId',
        options: Options(headers: {'Authorization': 'bearer $token'}),
      );
    } on DioException catch (e) {
      throw BatchExtractException('查询任务状态失败: ${e.message ?? e.type.name}');
    }

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) throw const BatchExtractException('轮询响应中无 data 字段');
    return data;
  }

  /// 从 JSONL URL 下载结果并解析为 (合并Markdown, 图片Map)。
  ///
  /// JSONL 每行格式：{"result": {"layoutParsingResults": [...]}}
  /// 与同步 API 的 result 结构相同，因此可复用 [DocExtractService.saveResult]。
  Future<(String, Map<String, String>)> _parseJsonlResult(
    String jsonlUrl,
  ) async {
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        jsonlUrl,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw BatchExtractException('下载提取结果失败: ${e.message ?? e.type.name}');
    }

    final markdownParts = <String>[];
    final allImages = <String, String>{};

    for (final line in (response.data ?? '').trim().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        final result = json['result'] as Map<String, dynamic>?;
        final parsingResults = result?['layoutParsingResults'] as List<dynamic>?;
        if (parsingResults == null) continue;

        for (final page in parsingResults) {
          final mdSection = page['markdown'] as Map<String, dynamic>?;
          if (mdSection == null) continue;
          markdownParts.add(mdSection['text'] as String? ?? '');
          final rawImages = mdSection['images'] as Map<String, dynamic>?;
          if (rawImages != null) {
            for (final entry in rawImages.entries) {
              allImages[entry.key] = entry.value.toString();
            }
          }
        }
      } catch (e) {
        debugPrint('[BatchExtract] 解析 JSONL 行失败: $e');
      }
    }

    return (markdownParts.join('\n\n'), allImages);
  }

  // ─── 主方法 ────────────────────────────────────────────────────────────────

  /// 批量异步提取文档，返回 documentId → HTML 保存路径（null 表示失败）。
  ///
  /// [onProgress] 在整体进度变化时回调（含所有 Job 的状态快照）。
  /// [onJobUpdate] 在单个 Job 状态变化时回调（更细粒度）。
  Future<BatchExtractResults> extractBatch({
    required List<BatchExtractItem> items,
    required String apiBaseUrl,
    required String token,
    required DocExtractApiState state,
    void Function(BatchExtractProgress)? onProgress,
    void Function(BatchJobStatus)? onJobUpdate,
    CancelToken? cancelToken,
  }) async {
    final jobStatuses = items
        .map((item) => BatchJobStatus(
              documentId: item.documentId,
              title: item.title,
            ))
        .toList();
    final results = <String, String?>{};
    final jobUrl = _jobUrl(apiBaseUrl);

    // Phase 1：依次提交所有 Job，间隔 500ms 以避免 API 限流
    for (int i = 0; i < items.length; i++) {
      if (cancelToken?.isCancelled == true) break;
      final item = items[i];
      final status = jobStatuses[i];

      onProgress?.call(_buildProgress(jobStatuses, item.title));

      try {
        final jobId = await _submitJob(
          filePath: item.filePath,
          jobUrl: jobUrl,
          token: token,
          state: state,
          cancelToken: cancelToken,
        );
        status.jobId = jobId;
        status.state = BatchJobState.submitted;
      } on DioException {
        // CancelToken 取消时 Dio 抛出 DioException，退出提交循环
        status.state = BatchJobState.cancelled;
        results[item.documentId] = null;
        onJobUpdate?.call(status);
        break;
      } catch (e) {
        status.state = BatchJobState.failed;
        status.error = e.toString();
        results[item.documentId] = null;
      }

      onJobUpdate?.call(status);
      onProgress?.call(_buildProgress(jobStatuses, item.title));

      if (i < items.length - 1 && cancelToken?.isCancelled != true) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // Phase 2：轮询所有 submitted/running Job 直到全部结束
    while (cancelToken?.isCancelled != true) {
      final running = jobStatuses
          .where((s) =>
              s.state == BatchJobState.submitted ||
              s.state == BatchJobState.running)
          .toList();
      if (running.isEmpty) break;

      for (final status in running) {
        if (cancelToken?.isCancelled == true) break;
        if (status.jobId == null) continue;

        try {
          final data = await _pollOnce(status.jobId!, jobUrl, token);
          switch (data['state'] as String? ?? '') {
            case 'pending':
              status.state = BatchJobState.submitted;

            case 'running':
              status.state = BatchJobState.running;
              final prog = data['extractProgress'] as Map?;
              status.extractedPages = (prog?['extractedPages'] as int?) ?? 0;
              status.totalPages = (prog?['totalPages'] as int?) ?? 0;

            case 'done':
              final jsonlUrl =
                  (data['resultUrl'] as Map?)?['jsonUrl'] as String?;
              if (jsonlUrl != null) {
                try {
                  final (markdown, images) = await _parseJsonlResult(jsonlUrl);
                  final item = items
                      .firstWhere((i) => i.documentId == status.documentId);
                  final extractResult =
                      DocExtractResult(markdown: markdown, images: images);
                  final savedPath = await DocExtractService.instance
                      .saveResult(item.filePath, extractResult, token: token);
                  status.savedPath = savedPath;
                  results[status.documentId] = savedPath;
                } catch (e) {
                  status.error = '保存结果失败: $e';
                  results[status.documentId] = null;
                }
              } else {
                results[status.documentId] = null;
              }
              status.state = BatchJobState.done;

            case 'failed':
              status.state = BatchJobState.failed;
              status.error = data['errorMsg'] as String? ?? '提取失败';
              results[status.documentId] = null;
          }
        } catch (e) {
          debugPrint('[BatchExtract] 轮询出错 (${status.documentId}): $e');
        }

        onJobUpdate?.call(status);
      }

      onProgress?.call(_buildProgress(jobStatuses, ''));

      final stillRunning = jobStatuses.any((s) =>
          s.state == BatchJobState.submitted ||
          s.state == BatchJobState.running);
      if (stillRunning && cancelToken?.isCancelled != true) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    // 取消时将所有未完成任务标记为 cancelled
    if (cancelToken?.isCancelled == true) {
      for (final status in jobStatuses) {
        if (status.state == BatchJobState.submitted ||
            status.state == BatchJobState.running) {
          status.state = BatchJobState.cancelled;
          results[status.documentId] = null;
          onJobUpdate?.call(status);
        }
      }
    }

    return results;
  }
}
