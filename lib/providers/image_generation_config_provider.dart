import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

const kDefaultSummaryImagePrompt = '''
A detailed scientific infographic in the style of a Cell journal highlight summary. White or very light grey background. Clean vector-like line art, thin dark grey outlines. The layout includes a title, short explanatory text blocks, and simple diagram panels connected by arrows, presenting key findings in a structured, readable flow. Restrained color palette: soft muted blue, warm pale grey, very pale desaturated orange for functional coding only. No purple, no large filled color blocks, no gradients, no shadows, no 3D, no photorealistic rendering, no chaotic or dense text, no empty minimal look. Sans-serif labels, editorial and precise.
''';

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

const kSummaryFidelityOptions = <String, String>{
  'auto': '自动',
  'standard': '标准',
  'high': '高',
};

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
const _kPrompt = 'image_generation_prompt';
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
    final prompt =
        box.get(_kPrompt, defaultValue: kDefaultSummaryImagePrompt) as String;
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
      fidelity: kSummaryFidelityOptions.containsKey(fidelity)
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
    if (!kSummaryFidelityOptions.containsKey(value)) return;
    state = state.copyWith(fidelity: value);
    await GStorage.setting.put(_kFidelity, value);
  }

  Future<void> setPrompt(String value) async {
    state = state.copyWith(prompt: value);
    await GStorage.setting.put(_kPrompt, value);
  }

  Future<void> resetPrompt() async {
    state = state.copyWith(prompt: kDefaultSummaryImagePrompt);
    await GStorage.setting.delete(_kPrompt);
  }

  Future<void> setMaxReferenceImages(int value) async {
    final normalized = value.clamp(1, 14).toInt();
    state = state.copyWith(maxReferenceImages: normalized);
    await GStorage.setting.put(_kMaxReferenceImages, normalized);
  }

  Future<void> resetAll() async {
    state = const ImageGenerationConfig();
    final box = GStorage.setting;
    await box.delete(_kAspectRatio);
    await box.delete(_kFidelity);
    await box.delete(_kPrompt);
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
