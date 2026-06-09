import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';
import 'doc_extract_service.dart';
import '../core/app_logger.dart';

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

/// documentId → 已保存的阅读版 Markdown 路径（null 表示该文献提取失败）
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

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 300),
      sendTimeout: const Duration(seconds: 120),
    ),
  );

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

  /// 每组并发提交的最大 Job 数
  static const int _maxConcurrent = 5;

  static const _jobApiUrl =
      'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';

  /// API 返回 `extractedPages`/`totalPages` 可能是 String 或 int。
  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 从 DioException.response?.data 安全提取 Map（可能是 String/null）。
  static Map<String, dynamic>? _safeResponseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  /// 检查 API 响应的业务错误码，非 0 时抛出含人类可读描述的异常。
  static void _checkApiResponse(Map<String, dynamic>? body) {
    if (body == null) return;
    final code = body['code'];
    if (code == null || code == 0) return;
    final msg = body['msg'] as String? ?? '';
    final desc = switch (code) {
      10003 => '文件超过大小限制 (上传 50MB / URL 200MB)',
      10006 => '页数超过限制 (最多 1000 页)',
      10009 => '同一 batchId 最多 100 个任务',
      10010 => '服务队列已满，请稍后重试',
      12001 => '今日页数配额已用完',
      12002 => '请求频率过高',
      _ => msg,
    };
    throw BatchExtractException('[$code] $desc');
  }

  BatchExtractProgress _buildProgress(
    List<BatchJobStatus> statuses,
    String currentTitle,
  ) {
    final succeeded = statuses
        .where((s) => s.state == BatchJobState.done)
        .length;
    final failed = statuses
        .where(
          (s) =>
              s.state == BatchJobState.failed ||
              s.state == BatchJobState.cancelled,
        )
        .length;
    return BatchExtractProgress(
      total: statuses.length,
      completed: succeeded + failed,
      succeeded: succeeded,
      failed: failed,
      currentTitle: currentTitle,
      statuses: statuses
          .map(
            (s) => BatchJobStatus(
              documentId: s.documentId,
              title: s.title,
              state: s.state,
              jobId: s.jobId,
              error: s.error,
              extractedPages: s.extractedPages,
              totalPages: s.totalPages,
              savedPath: s.savedPath,
            ),
          )
          .toList(),
    );
  }

  // ─── Job 提交与轮询 ────────────────────────────────────────────────────────

  /// 以 multipart/form-data 提交提取任务，返回 jobId。
  ///
  /// v2 API 使用 `bearer` 授权头（小写），且文件以原始字节上传而非 base64。
  /// [batchId] 用于将多个 Job 归为同一批次，支持批量状态查询。
  Future<String> _submitJob({
    required String filePath,
    required String jobUrl,
    required String token,
    required DocExtractApiState state,
    String? batchId,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: p.basename(filePath),
      ),
      'model': 'PaddleOCR-VL-1.6',
      'optionalPayload': jsonEncode(DocExtractService.buildOptions(state)),
      // ignore: use_null_aware_elements
      if (batchId != null) 'batchId': batchId,
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
      _checkApiResponse(_safeResponseMap(e.response?.data));
      throw BatchExtractException('提交任务失败: ${e.message ?? e.type.name}');
    }

    log.d('[BatchExtract] submit response: code=${response.data?['code']}, msg=${response.data?['msg']}');
    _checkApiResponse(response.data);
    final jobId = response.data?['data']?['jobId'] as String?;
    if (jobId == null) {
      final msg = response.data?['msg'] as String? ?? '响应中无 jobId';
      log.d('[BatchExtract] submit failed: no jobId, full response=${response.data}');
      throw BatchExtractException('提交任务失败: $msg');
    }
    log.d('[BatchExtract] submit ok: jobId=$jobId');
    return jobId;
  }

  /// 查询单个 Job 的当前状态数据（逐个轮询回退用）。
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
      if (e.response?.statusCode == 429) rethrow;
      _checkApiResponse(_safeResponseMap(e.response?.data));
      throw BatchExtractException('查询任务状态失败: ${e.message ?? e.type.name}');
    }

    _checkApiResponse(response.data);
    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) throw const BatchExtractException('轮询响应中无 data 字段');
    return data;
  }

  /// 通过 batchId 批量查询所有 Job 的状态（一次请求代替 N 次）。
  Future<List<Map<String, dynamic>>> _pollBatch(
    String batchId,
    String jobUrl,
    String token,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(
        '$jobUrl/batch/$batchId',
        options: Options(headers: {'Authorization': 'bearer $token'}),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) rethrow;
      _checkApiResponse(_safeResponseMap(e.response?.data));
      throw BatchExtractException('批量查询状态失败: ${e.message ?? e.type.name}');
    }

    _checkApiResponse(response.data);
    final data = response.data?['data'];
    log.d('[BatchExtract] pollBatch response data type=${data.runtimeType}, keys=${data is Map<String, dynamic> ? data.keys.toList() : 'N/A'}');
    if (data is Map<String, dynamic>) {
      final results = data['extractResult'];
      if (results is List) {
        return results.whereType<Map<String, dynamic>>().toList();
      }
    }
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  /// 从 JSONL URL 下载结果，展平为页面数组后返回 [DocExtractResult]。
  Future<DocExtractResult> _parseJsonlResult(String jsonlUrl) async {
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        jsonlUrl,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw BatchExtractException('下载提取结果失败: ${e.message ?? e.type.name}');
    }

    final rawContent = response.data ?? '';
    final markdownParts = <String>[];
    final allImages = <String, String>{};
    final allPages = <Map<String, dynamic>>[];

    for (final line in rawContent.trim().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        final result = json['result'] as Map<String, dynamic>?;
        final parsingResults =
            result?['layoutParsingResults'] as List<dynamic>?;
        if (parsingResults == null) continue;

        for (final page in parsingResults) {
          allPages.add(page as Map<String, dynamic>);
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
        log.d('[BatchExtract] 解析结果行失败: $e');
      }
    }

    return DocExtractResult(
      rawMarkdown: markdownParts.join('\n\n'),
      images: allImages,
      jsonContent: jsonEncode(allPages),
    );
  }

  /// 从轮询数据中更新单个 Job 的状态，完成时自动下载并保存结果。
  Future<void> _updateStatusFromData(
    BatchJobStatus status,
    Map<String, dynamic> data,
    List<BatchExtractItem> items,
    Map<String, String?> results,
  ) async {
    switch (data['state'] as String? ?? '') {
      case 'pending':
        status.state = BatchJobState.submitted;

      case 'running':
        status.state = BatchJobState.running;
        final prog = data['extractProgress'] as Map?;
        status.extractedPages = _toInt(prog?['extractedPages']);
        status.totalPages = _toInt(prog?['totalPages']);

      case 'done':
        final resultUrl = data['resultUrl'] as Map?;
        final jsonlUrl = resultUrl?['jsonUrl'] as String?;
        final markdownUrl = resultUrl?['markdownUrl'] as String?;

        if (jsonlUrl != null) {
          try {
            final extractResult = await _parseJsonlResult(jsonlUrl);
            final item = items.firstWhere(
              (i) => i.documentId == status.documentId,
            );
            final savedPath = await DocExtractService.instance.saveResult(
              item.filePath,
              extractResult,
              token: null,
              title: item.title,
            );
            status.savedPath = savedPath;
            results[status.documentId] = savedPath;
          } catch (e) {
            status.error = '保存结果失败: $e';
            results[status.documentId] = null;
          }
        } else if (markdownUrl != null) {
          // 回退：仅有 Markdown URL 时直接获取纯文本（无图片信息）
          try {
            final mdResponse = await _dio.get<String>(
              markdownUrl,
              options: Options(responseType: ResponseType.plain),
            );
            final markdown = mdResponse.data ?? '';
            final item = items.firstWhere(
              (i) => i.documentId == status.documentId,
            );
            final extractResult = DocExtractResult(
              rawMarkdown: markdown,
              images: {},
            );
            final savedPath = await DocExtractService.instance.saveResult(
              item.filePath,
              extractResult,
              token: null,
              title: item.title,
            );
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
  }

  // ─── 单文档异步提取 ─────────────────────────────────────────────────────────

  /// 轮询间隔（秒）
  static const _pollInterval = Duration(seconds: 5);

  /// 提交单个文档的异步提取任务，轮询直到完成，返回原始 [DocExtractResult]。
  ///
  /// 这是单文档场景的首选入口，与 [extractBatch] 使用相同的 Job API。
  /// 调用方自行决定是否 [DocExtractService.saveResult]。
  Future<DocExtractResult> extractSingle({
    required String filePath,
    required String token,
    required DocExtractApiState state,
    void Function(String status, int extractedPages, int totalPages)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    final jobUrl = _jobApiUrl;

    // 1. 提交 Job
    onProgress?.call('正在提交任务…', 0, 0);
    final jobId = await _submitJob(
      filePath: filePath,
      jobUrl: jobUrl,
      token: token,
      state: state,
      cancelToken: cancelToken,
    );

    // 2. 轮询直到完成
    while (true) {
      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      }

      await Future.delayed(_pollInterval);

      final data = await _pollOnce(jobId, jobUrl, token);
      final jobState = data['state'] as String? ?? '';

      switch (jobState) {
        case 'pending':
          onProgress?.call('排队中…', 0, 0);
        case 'running':
          final prog = data['extractProgress'] as Map?;
          final extracted = _toInt(prog?['extractedPages']);
          final total = _toInt(prog?['totalPages']);
          onProgress?.call('正在提取…', extracted, total);
        case 'done':
          final resultUrl = data['resultUrl'] as Map?;
          final jsonlUrl = resultUrl?['jsonUrl'] as String?;
          if (jsonlUrl != null) {
            onProgress?.call('正在下载结果…', 0, 0);
            return _parseJsonlResult(jsonlUrl);
          }
          // 回退：仅有 Markdown URL
          final markdownUrl = resultUrl?['markdownUrl'] as String?;
          if (markdownUrl != null) {
            final mdResponse = await _dio.get<String>(
              markdownUrl,
              options: Options(responseType: ResponseType.plain),
            );
            return DocExtractResult(
              rawMarkdown: mdResponse.data ?? '',
              images: {},
            );
          }
          throw const BatchExtractException('任务完成但无结果 URL');
        case 'failed':
          final errorMsg = data['errorMsg'] as String? ?? '提取失败';
          throw BatchExtractException(errorMsg);
      }
    }
  }

  // ─── 批量提取 ──────────────────────────────────────────────────────────────

  /// 批量异步提取文档，返回 documentId → 保存路径（null 表示失败）。
  ///
  /// 优化策略：
  /// - 并发提交（每组 [_maxConcurrent] 个），减少提交阶段耗时
  /// - 使用 batchId 批量查询状态（1 次请求替代 N 次），降低 API 调用量
  /// - 429 限流时指数退避，避免请求风暴
  /// - 批量查询失败时自动回退到逐个轮询
  Future<BatchExtractResults> extractBatch({
    required List<BatchExtractItem> items,
    required String token,
    required DocExtractApiState state,
    void Function(BatchExtractProgress)? onProgress,
    void Function(BatchJobStatus)? onJobUpdate,
    CancelToken? cancelToken,
  }) async {
    final jobStatuses = items
        .map(
          (item) =>
              BatchJobStatus(documentId: item.documentId, title: item.title),
        )
        .toList();
    final results = <String, String?>{};
    final jobUrl = _jobApiUrl;
    final batchId = 'nr_${DateTime.now().millisecondsSinceEpoch}';

    log.d('[BatchExtract] === extractBatch start: ${items.length} items, batchId=$batchId ===');
    // Phase 1：并发提交 Job（每组最多 _maxConcurrent 个）
    for (int i = 0; i < items.length; i += _maxConcurrent) {
      if (cancelToken?.isCancelled == true) break;

      final end = (i + _maxConcurrent).clamp(0, items.length);
      final groupIndices = List.generate(end - i, (j) => i + j);

      onProgress?.call(_buildProgress(jobStatuses, items[i].title));

      await Future.wait(
        groupIndices.map((idx) async {
          final item = items[idx];
          final status = jobStatuses[idx];
          try {
            final jobId = await _submitJob(
              filePath: item.filePath,
              jobUrl: jobUrl,
              token: token,
              state: state,
              batchId: batchId,
              cancelToken: cancelToken,
            );
            status.jobId = jobId;
            status.state = BatchJobState.submitted;
          } on DioException catch (e) {
            if (e.type == DioExceptionType.cancel) {
              status.state = BatchJobState.cancelled;
            } else {
              status.state = BatchJobState.failed;
              status.error = '提交任务失败: ${e.message ?? e.type.name}';
            }
            results[item.documentId] = null;
          } catch (e) {
            status.state = BatchJobState.failed;
            status.error = e.toString();
            results[item.documentId] = null;
          }
          onJobUpdate?.call(status);
        }),
      );

      onProgress?.call(
        _buildProgress(
          jobStatuses,
          items[(end - 1).clamp(0, items.length - 1)].title,
        ),
      );
    }

    // 建立 jobId → status 查找表
    final jobIdToStatus = <String, BatchJobStatus>{};
    for (final s in jobStatuses) {
      if (s.jobId != null) jobIdToStatus[s.jobId!] = s;
    }

    // Phase 2：轮询所有 Job 直到全部结束（优先使用 batchId 批量查询）
    final submitted = jobStatuses.where((s) => s.jobId != null).length;
    final failedSubmit = jobStatuses.where((s) => s.state == BatchJobState.failed).length;
    log.d('[BatchExtract] === Phase 1 done: $submitted submitted, $failedSubmit failed ===');
    for (final s in jobStatuses) {
      log.d('[BatchExtract]   ${s.documentId}: state=${s.state.name}, jobId=${s.jobId}, error=${s.error}');
    }
    int pollDelayMs = 5000;
    bool useBatchPoll = true;

    while (cancelToken?.isCancelled != true) {
      final activeStatuses = jobStatuses
          .where(
            (s) =>
                s.state == BatchJobState.submitted ||
                s.state == BatchJobState.running,
          )
          .toList();
      if (activeStatuses.isEmpty) break;
      log.d('[BatchExtract] poll tick: ${activeStatuses.length} active, mode=${useBatchPoll ? "batch" : "individual"}');

      try {
        if (useBatchPoll) {
          // 批量查询：1 次请求获取所有 Job 状态
          final jobDataList = await _pollBatch(batchId, jobUrl, token);
          log.d('[BatchExtract] pollBatch returned ${jobDataList.length} items');
          if (jobDataList.isEmpty && activeStatuses.isNotEmpty) {
            // 端点返回空列表，回退到逐个查询
            log.d('[BatchExtract] batch returned empty, falling back to individual');
            useBatchPoll = false;
            continue;
          }
          for (final data in jobDataList) {
            final jobId = data['jobId'] as String?;
            if (jobId == null) continue;
            final status = jobIdToStatus[jobId];
            if (status == null) continue;
            // 跳过已完成/失败/取消的 Job
            if (status.state != BatchJobState.submitted &&
                status.state != BatchJobState.running) {
              continue;
            }
            await _updateStatusFromData(status, data, items, results);
            onJobUpdate?.call(status);
          }
        } else {
          // 回退：逐个查询
          for (final status in activeStatuses) {
            if (cancelToken?.isCancelled == true) break;
            if (status.jobId == null) continue;
            try {
              final data = await _pollOnce(status.jobId!, jobUrl, token);
              await _updateStatusFromData(status, data, items, results);
              onJobUpdate?.call(status);
            } on DioException catch (e) {
              if (e.response?.statusCode == 429) rethrow;
              log.d('[BatchExtract] 轮询出错 (${status.documentId}): $e');
            } catch (e) {
              log.d('[BatchExtract] 轮询出错 (${status.documentId}): $e');
            }
          }
        }
        pollDelayMs = 5000;
      } on DioException catch (e) {
        if (e.response?.statusCode == 429) {
          // 限流 → 指数退避
          pollDelayMs = (pollDelayMs * 1.5).toInt().clamp(5000, 30000);
          log.d('[BatchExtract] 触发限流 (429)，退避 ${pollDelayMs}ms');
        } else if (useBatchPoll) {
          // 批量端点不可用 → 回退到逐个轮询
          useBatchPoll = false;
          log.d('[BatchExtract] 批量查询失败，回退到逐个轮询');
          continue;
        }
      } catch (e) {
        log.d('[BatchExtract] 轮询出错: $e');
      }

      onProgress?.call(_buildProgress(jobStatuses, ''));

      final stillRunning = jobStatuses.any(
        (s) =>
            s.state == BatchJobState.submitted ||
            s.state == BatchJobState.running,
      );
      if (stillRunning && cancelToken?.isCancelled != true) {
        await Future.delayed(Duration(milliseconds: pollDelayMs));
      }
    }

    // 取消时将所有未完成任务标记为 cancelled
    if (cancelToken?.isCancelled == true) {
      for (final status in jobStatuses) {
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
}
