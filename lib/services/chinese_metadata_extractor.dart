import 'dart:math';

import 'document_metadata_parser.dart';
import 'identifier_parser.dart';

/// 从中文期刊 PDF 首页正文文本中提取元数据。
///
/// pdfrx 的 `loadText()` 返回线性化纯文本（无字号/坐标），因此只能靠文本模式锚点：
/// - **DOI / 年份**：强信号正则，可靠
/// - **作者**：以机构行 `（1.…` 或「摘要/关键词」等正文起始作终止锚点，提取标题与
///   锚点之间的中文人名逗号序列
/// - **期刊**：标题之前的页眉区域，清理卷期/日期/英文后匹配期刊名后缀
///
/// 各字段独立提取，任一失败只丢该字段，不影响其他。
class ChineseMetadataExtractor {
  ChineseMetadataExtractor._();

  // 年份：四位数 + 「年」，避免抓到 DOI/卷号里的数字
  static final _yearPattern = RegExp(r'((?:19|20)\d{2})\s*年');

  // 文章编号里的出版年：`文章编号：ISSN号(YYYY)…`（compact 已去空白）
  static final _articleNumberYearPattern = RegExp(
    r'文章编号[：:][\d-]+[（(]((?:19|20)\d{2})[）)]',
  );

  // 正文 DOI（与 PdfIdentifierExtractor 同款非锚定正则）
  static final _doiPattern = RegExp(
    r'10\.\d{4,}/[^\s"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  // 作者区域的终止锚点：编号机构行 `（1.`，或「摘要 / 关键词 / Abstract」等正文
  // 起始标记。作者行几乎总是紧跟其一，用最早出现者切断，避免末位作者黏连正文。
  //
  // 机构行必须是「括号 + 1 + 点/顿号」，不能放宽成「括号 + 任意数字」——否则会错把
  // 文章编号里的 `1000-0747(2026)` 当成锚点，导致作者区域吞进「文章编号」等页眉词。
  static final _authorEndPattern = RegExp(
    r'[（(]\s*1\s*[.．、]|摘\s*要|关\s*键\s*词|Abstract|Key\s*words',
    caseSensitive: false,
  );

  // 中文期刊首页常见的非人名词（2-4 字），防御性排除，避免被当成作者。
  static const _nonNameWords = {
    '文章编号', '基金项目', '中图分类', '文献标识', '收稿日期', '修回日期',
    '通讯作者', '第一作者', '作者简介', '引用格式', '网络出版', '网络首发',
    '参考文献', '摘要', '关键词',
  };

  // 作者/角标分隔符
  static final _authorDelimiterPattern = RegExp(r'[,，、;；]');

  // 单个中文 token（2-4 字），用于在分隔段内定位人名
  static final _chineseNamePattern = RegExp(r'[一-鿿]{2,4}');

  // 单个汉字，用于判断分隔段内是否残留其他中文（排除标题词黏连）
  static final _singleHanPattern = RegExp(r'[一-鿿]');

  // 期刊名后缀：明确的中文期刊命名词，避免在正文里乱匹配
  static final _journalPattern = RegExp(
    r'[一-鿿]{2,12}(?:学报|学刊|杂志|通报|导报|公报|评论|论坛|科学|医学|科技|工程|译丛|文摘|研究|进展|报告|纪要|年鉴|快报|通讯|集刊|丛刊|学术|综述)',
  );

  static final _volumeIssuePattern = RegExp(r'第\s*\d+\s*[卷期]');
  static final _yearMonthPattern = RegExp(
    r'(?:19|20)\d{2}\s*年(?:\s*\d{1,2}\s*月)?',
  );
  static final _asciiNoisePattern = RegExp(r'[A-Za-z0-9．.:：/\-]+');
  static final _whitespacePattern = RegExp(r'\s');

  /// 从首页文本解析元数据。[knownTitle] 用于剥离标题、定位页眉/作者区域。
  static DocumentMetadata parseFromText(String? text, {String? knownTitle}) {
    if (text == null || text.trim().isEmpty) return const DocumentMetadata();

    // 去空白文本：中文期刊首页的人名/逗号/标题在去空白后仍连续，便于锚点定位
    final compact = text.replaceAll(_whitespacePattern, '');

    final doi = _extractDoi(text);
    final year = _extractYear(text, compact, doi);

    // 同时定位标题的起止下标：作者用 titleEnd（标题后）、期刊用 titleStart（标题前）
    final needle = knownTitle?.replaceAll(_whitespacePattern, '');
    var titleStart = (needle != null && needle.isNotEmpty)
        ? compact.indexOf(needle)
        : -1;
    // 精确匹配失败时尝试 Dice bigram 模糊锚定
    if (titleStart < 0 && needle != null && needle.length >= 4) {
      titleStart = _fuzzyLocate(compact, needle, threshold: 0.7);
    }
    final titleEnd = titleStart >= 0 && needle != null
        ? titleStart + needle.length
        : -1;

    var authors = _extractAuthors(compact, titleEnd);
    // 标题锚定完全失败时，用无锚定策略从正文前部扫描作者
    if (authors.isEmpty && titleEnd < 0) {
      authors = _extractAuthorsUnanchored(compact);
    }
    final journal = _extractJournal(compact, titleStart);

    return DocumentMetadata(
      authors: authors,
      journal: journal,
      year: year,
      doi: doi,
    );
  }

  /// 是否为中文期刊首页常见的非人名词（如「文章编号」）。
  /// 供元数据修复检测复用：作者字段里出现这类词，说明此前误提取，需要重修。
  static bool isNonPersonName(String name) => _nonNameWords.contains(name.trim());

  static String? _extractDoi(String text) {
    final match = _doiPattern.firstMatch(text);
    if (match == null) return null;
    // DOI 大小写不敏感，统一小写（与 IdentifierResolver 一致）
    return IdentifierParser.normalizeDoi(match.group(0))?.toLowerCase();
  }

  static String? _extractYear(String text, String compact, String? doi) {
    // 1. 正文「YYYY 年」——最可靠
    final ym = _yearPattern.firstMatch(text);
    if (ym != null) return ym.group(1);
    // 2. 文章编号 `ISSN(YYYY)期-页-数` 括号里是出版年，比 DOI 里的投稿年可靠。
    //    用在 compact 上，容忍原文里的空格（如「文章编号： 1000-0747(2026)」）。
    final am = _articleNumberYearPattern.firstMatch(compact);
    if (am != null) return am.group(1);
    // 3. 兜底：中文 DOI 末段常含年份，如 .../...2026.01.040
    if (doi != null) {
      final m = RegExp(r'(?:19|20)\d{2}').firstMatch(doi);
      if (m != null) return m.group(0);
    }
    return null;
  }

  /// 提取作者：机构行锚点之前的中文人名序列。
  static List<String> _extractAuthors(String compact, int titleEnd) {
    final from = titleEnd >= 0 ? titleEnd : 0;
    if (from >= compact.length) return const [];

    final region = compact.substring(from);
    final endMatch = _authorEndPattern.firstMatch(region);
    // 没有终止锚点时，退守标题后 60 字符（多数作者行落在此范围）
    final authorSeg = endMatch != null
        ? region.substring(0, endMatch.start)
        : region.substring(0, min(region.length, 60));

    final names = <String>[];
    for (final part in authorSeg.split(_authorDelimiterPattern)) {
      final match = _chineseNamePattern.firstMatch(part);
      if (match == null) continue;
      final name = match.group(0)!;
      if (_nonNameWords.contains(name)) continue;
      // 该分隔段去掉人名后若仍残留汉字，说明黏连了标题/其他词，丢弃以免误判
      final rest = part.replaceFirst(name, '');
      if (!_singleHanPattern.hasMatch(rest)) names.add(name);
    }
    return names;
  }

  /// 提取期刊名：标题之前的页眉区域，清理卷期/日期/英文后匹配期刊后缀。
  ///
  /// 要求标题定位成功（titleStart > 0），否则页眉边界不可靠，保守留空。
  static String? _extractJournal(String compact, int titleStart) {
    if (titleStart <= 0) return null;

    final header = compact
        .substring(0, titleStart)
        .replaceAll(_volumeIssuePattern, '')
        .replaceAll(_yearMonthPattern, '')
        .replaceAll(_asciiNoisePattern, '');

    return _journalPattern.firstMatch(header)?.group(0);
  }

  // ── 模糊标题锚定 ─────────────────────────────────────────────────────

  /// 在 [text] 中模糊定位 [needle]：滑动窗口 + Dice bigram 相似度。
  /// 返回最佳匹配的起始下标，低于 [threshold] 返回 -1。
  static int _fuzzyLocate(String text, String needle, {double threshold = 0.7}) {
    final nLen = needle.length;
    if (nLen < 2 || text.length < nLen) return -1;

    final needleBigrams = _bigrams(needle);
    final searchEnd = min(text.length, nLen * 6);
    var bestScore = 0.0;
    var bestIdx = -1;

    for (var i = 0; i <= searchEnd - nLen; i++) {
      final window = text.substring(i, i + nLen);
      final score = _diceSimilarity(needleBigrams, nLen, window);
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
    return bestScore >= threshold ? bestIdx : -1;
  }

  static Map<String, int> _bigrams(String s) {
    final m = <String, int>{};
    for (var i = 0; i < s.length - 1; i++) {
      final bg = s.substring(i, i + 2);
      m[bg] = (m[bg] ?? 0) + 1;
    }
    return m;
  }

  static double _diceSimilarity(
    Map<String, int> aBigrams,
    int aLen,
    String b,
  ) {
    if (aLen < 2 || b.length < 2) return 0.0;
    final bBigrams = _bigrams(b);
    var intersection = 0;
    for (final e in aBigrams.entries) {
      final bCount = bBigrams[e.key];
      if (bCount != null) intersection += min(e.value, bCount);
    }
    return 2 * intersection / (aLen - 1 + b.length - 1);
  }

  // ── 无锚定作者回退 ───────────────────────────────────────────────────

  // 连续中文名 + 分隔符（逗号/顿号）的序列模式：至少 2 个名字
  static final _authorSequencePattern = RegExp(
    r'(?:[一-鿿]{2,4}[,，、;；\d\s*]*){2,}[一-鿿]{2,4}',
  );

  /// 标题锚定失败时的回退：在正文前 300 字符内寻找作者序列。
  static List<String> _extractAuthorsUnanchored(String compact) {
    final region = compact.substring(0, min(compact.length, 300));
    final seqMatch = _authorSequencePattern.firstMatch(region);
    if (seqMatch == null) return const [];

    final segment = seqMatch.group(0)!;
    final names = <String>[];
    for (final part in segment.split(_authorDelimiterPattern)) {
      final m = _chineseNamePattern.firstMatch(part);
      if (m == null) continue;
      final name = m.group(0)!;
      if (_nonNameWords.contains(name)) continue;
      final rest = part.replaceFirst(name, '');
      if (!_singleHanPattern.hasMatch(rest)) names.add(name);
    }
    return names.length >= 2 ? names : const [];
  }
}
