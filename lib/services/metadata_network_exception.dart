import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../core/l10n.dart';
import '../router/app_router.dart';

enum MetadataNetworkFailure {
  certificate,
  proxy,
  timeout,
  notFound,
  connection,
  request,
}

class MetadataNetworkException implements Exception {
  const MetadataNetworkException(this.reason);
  final MetadataNetworkFailure reason;

  factory MetadataNetworkException.fromDio(
    DioException error, {
    bool usesProxy = false,
  }) {
    if (CancelToken.isCancel(error)) throw error;
    final reason = switch (error) {
      DioException(type: DioExceptionType.badCertificate) =>
        MetadataNetworkFailure.certificate,
      DioException(error: HandshakeException()) =>
        MetadataNetworkFailure.certificate,
      DioException(error: TlsException()) => MetadataNetworkFailure.certificate,
      DioException(response: Response(statusCode: 407)) =>
        MetadataNetworkFailure.proxy,
      DioException(response: Response(statusCode: 404)) =>
        MetadataNetworkFailure.notFound,
      DioException(
        type: DioExceptionType.connectionTimeout ||
            DioExceptionType.sendTimeout ||
            DioExceptionType.receiveTimeout,
      ) =>
        MetadataNetworkFailure.timeout,
      DioException(type: DioExceptionType.connectionError) =>
        usesProxy
            ? MetadataNetworkFailure.proxy
            : MetadataNetworkFailure.connection,
      _ => MetadataNetworkFailure.request,
    };
    return MetadataNetworkException(reason);
  }

  @override
  String toString() {
    final l10n =
        rootNavigatorKey.currentContext?.l10n ??
        lookupAppLocalizations(const Locale('en'));
    return switch (reason) {
      MetadataNetworkFailure.certificate => l10n.metadataCertificateFailed,
      MetadataNetworkFailure.proxy => l10n.metadataProxyFailed,
      MetadataNetworkFailure.timeout => l10n.metadataRequestTimedOut,
      MetadataNetworkFailure.notFound => l10n.metadataNotFound,
      MetadataNetworkFailure.connection => l10n.metadataConnectionFailed,
      MetadataNetworkFailure.request => l10n.networkRequestFailedRetry,
    };
  }
}
