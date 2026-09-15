class MinerUParseOptions {
  MinerUParseOptions._();

  /// 当前只接入 VLM；Pipeline 的结构化输出暂不进入请求链路。
  static const onlyModel = 'vlm';
  static const languages = [
    'ch',
    'ch_server',
    'en',
    'japan',
    'korean',
    'chinese_cht',
    'ta',
    'te',
    'ka',
    'el',
    'th',
    'latin',
    'arabic',
    'cyrillic',
    'east_slavic',
    'devanagari',
  ];
  static const extraFormats = ['docx', 'html', 'latex'];
}
