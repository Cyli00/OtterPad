import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';
import '../services/prompt_store.dart';
import '../services/prompts.dart';

// 默认提示词文本在 Prompt Registry（services/prompts.dart）——
// 本文件只管理生图域的非 prompt 配置，prompt 的存取委托 PromptStore。

const kDefaultSummaryAspectRatio = '16:9';
const kDefaultSummaryFidelity = 'high';
const kDefaultSummaryMaxReferenceImages = 10;

const kSummaryAspectRatios = <String>[
  '1:1',
  '4:3',
  '3:2',
  '16:9',
  '21:9',
  '9:16',
];

const kSummaryFidelityKeys = <String>['auto', 'standard', 'high'];

class ImageGenerationConfig {
  final String aspectRatio;
  final String fidelity;
  final String prompt;
  final int maxReferenceImages;

  const ImageGenerationConfig({
    this.aspectRatio = kDefaultSummaryAspectRatio,
    this.fidelity = kDefaultSummaryFidelity,
    this.prompt = kDefaultSummaryImagePrompt,
    this.maxReferenceImages = kDefaultSummaryMaxReferenceImages,
  });

  bool get isPromptDefault =>
      prompt.trim() == kDefaultSummaryImagePrompt.trim();

  ImageGenerationConfig copyWith({
    String? aspectRatio,
    String? fidelity,
    String? prompt,
    int? maxReferenceImages,
  }) => ImageGenerationConfig(
    aspectRatio: aspectRatio ?? this.aspectRatio,
    fidelity: fidelity ?? this.fidelity,
    prompt: prompt ?? this.prompt,
    maxReferenceImages: maxReferenceImages ?? this.maxReferenceImages,
  );
}

const _kAspectRatio = 'image_generation_aspect_ratio';
const _kFidelity = 'image_generation_fidelity';
const _kMaxReferenceImages = 'image_generation_max_reference_images';

class ImageGenerationConfigNotifier
    extends StateNotifier<ImageGenerationConfig> {
  ImageGenerationConfigNotifier() : super(_load());

  static ImageGenerationConfig _load() {
    final box = GStorage.setting;
    final aspectRatio =
        box.get(_kAspectRatio, defaultValue: kDefaultSummaryAspectRatio)
            as String;
    final fidelity =
        box.get(_kFidelity, defaultValue: kDefaultSummaryFidelity) as String;
    final prompt = PromptStore.resolve(Prompts.summaryImage);
    final maxReferenceImages =
        box.get(
              _kMaxReferenceImages,
              defaultValue: kDefaultSummaryMaxReferenceImages,
            )
            as int;
    return ImageGenerationConfig(
      aspectRatio: kSummaryAspectRatios.contains(aspectRatio)
          ? aspectRatio
          : kDefaultSummaryAspectRatio,
      fidelity: kSummaryFidelityKeys.contains(fidelity)
          ? fidelity
          : kDefaultSummaryFidelity,
      prompt: prompt,
      maxReferenceImages: maxReferenceImages.clamp(1, 14).toInt(),
    );
  }

  Future<void> setAspectRatio(String value) async {
    if (!kSummaryAspectRatios.contains(value)) return;
    state = state.copyWith(aspectRatio: value);
    await GStorage.setting.put(_kAspectRatio, value);
  }

  Future<void> setFidelity(String value) async {
    if (!kSummaryFidelityKeys.contains(value)) return;
    state = state.copyWith(fidelity: value);
    await GStorage.setting.put(_kFidelity, value);
  }

  /// 空白输入 = 重置为默认（PromptStore 语义：用户清空但未配置新文本时
  /// 直接用当前默认）。生图 prompt 无必需占位符，保存不会被拒绝。
  Future<void> setPrompt(String value) async {
    await PromptStore.set(Prompts.summaryImage, value);
    state = state.copyWith(prompt: PromptStore.resolve(Prompts.summaryImage));
  }

  Future<void> resetPrompt() async {
    await PromptStore.reset(Prompts.summaryImage);
    state = state.copyWith(prompt: kDefaultSummaryImagePrompt);
  }

  Future<void> setMaxReferenceImages(int value) async {
    final normalized = value.clamp(1, 14).toInt();
    state = state.copyWith(maxReferenceImages: normalized);
    await GStorage.setting.put(_kMaxReferenceImages, normalized);
  }

  Future<void> resetAll() async {
    state = const ImageGenerationConfig();
    await PromptStore.reset(Prompts.summaryImage);
    final box = GStorage.setting;
    await box.delete(_kAspectRatio);
    await box.delete(_kFidelity);
    await box.delete(_kMaxReferenceImages);
  }
}

final imageGenerationConfigProvider =
    StateNotifierProvider<ImageGenerationConfigNotifier, ImageGenerationConfig>(
      (ref) => ImageGenerationConfigNotifier(),
    );

/// OpenAI gpt-image 预估费用（美元），基于尺寸+清晰度。
/// 仅 OpenAI provider 有意义；Gemini 无公开费用表。
double? estimateOpenAICost({
  required String aspectRatio,
  required String fidelity,
}) {
  final isSquare = aspectRatio == '1:1';
  return switch (fidelity) {
    'low' || 'auto' => isSquare ? 0.006 : 0.005,
    'standard' => isSquare ? 0.053 : 0.041,
    'high' => isSquare ? 0.211 : 0.165,
    _ => null,
  };
}
