import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

final localDocsProvider = FutureProvider<List<String>>((ref) async {
  final AssetManifest assetManifest =
      await AssetManifest.loadFromAssetBundle(rootBundle);
  
  final List<String> pdfAssets = assetManifest
      .listAssets()
      .where((path) => path.startsWith('assets/docs/') && path.toLowerCase().endsWith('.pdf'))
      .toList();
      
  return pdfAssets;
});
