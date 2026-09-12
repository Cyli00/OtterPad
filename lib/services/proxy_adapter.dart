import 'dart:io';

import 'package:dio/io.dart';

IOHttpClientAdapter buildProxyAdapter(String mode, String host, int port) {
  final adapter = IOHttpClientAdapter();
  switch (mode) {
    case 'custom':
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (_) => 'PROXY $host:$port';
        return client;
      };
    case 'system':
      adapter.createHttpClient = () => HttpClient();
    case 'none':
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (_) => 'DIRECT';
        return client;
      };
  }
  return adapter;
}
