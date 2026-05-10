import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 学术论文 back-matter（后置区域）统一检测器——单一数据源服务于：
/// - **翻译跳过**（[TranslationSkipSections] 通过 [detectByIds] 决定哪些段落不送翻译）
/// - **摘要图压缩**（[DocumentSummaryImageService] 通过 [detectFirstOffset] 截断 markdown）
/// - 未来其他后处理（reading time 估算、引文分析等）
///
/// **数据驱动**：所有 patterns 来自 `assets/config/back_matter_sections.json`，
/// JSON 按 L1/L2/L3 置信度分组，本服务把每条 pattern 反向归类到 6 个**用户可见
/// section**（references / acknowledgments / authors_contributions / funding_data
/// / supplementary_appendix / ethics_legends），让 UI 暴露语义清晰的勾选项而
/// 不是抽象的 L1/L2/L3。
///
/// **位置约束（继承自 JSON 的 L1/L2/L3 语义）**：
/// - L1 高置信度（References/Bibliography/Acknowledgments）：全文任意位置命中即生效
/// - L2 中置信度（Author contributions / Funding / Data / Appendix）：仅文档后 50% 命中
/// - L3 低置信度（Supplementary / Ethics / Figure legends）：仅文档后 40% 命中
///
/// **使用前必须 [init]**（启动时与 GStorage / AgentModelCapability 并行调用）。
class BackMatterDetector {
  BackMatterDetector._();
  static final BackMatterDetector instance = BackMatterDetector._();

  bool _initialized = false;

  /// 每个 section × level 编译好的合并正则（patterns 用 `|` 拼接）。
  /// `null` 表示该 section 在该 level 无对应 patterns。
  final Map<String, _SectionRegexes> _sectionRegexes = {};

  // ─── 公开静态：6 个用户可见 section 定义 ─────────────────────────────────
  //
  // **添加新 section**：
  // 1. 在此追加 [BackMatterSectionDef]，写好 `keywords`（反向匹配 patterns 用）
  // 2. JSON 已有 patterns 自动归类到新 section（首匹配优先）
  //
  // **关键词设计原则**：
  // - 用 pattern 中**最稳定的语义子串**（如 'reference' 而非 'references?'）
  // - 多语言并列（中/日/韩 + 主流欧洲语种 + 阿/希等区分度高的字符）
  // - 短/通用词放后面（避免 'data' 抢走 'data availability' 之类）
  // - 顺序敏感：列表中**靠前的 section 优先抢匹配**
  static const availableSections = <BackMatterSectionDef>[
    BackMatterSectionDef(
      id: 'references',
      label: '参考文献',
      defaultIgnore: true,
      keywords: [
        'reference', 'bibliograph', 'works cited', 'literature cited',
        'cited literature', 'cited work', 'cited reference',
        '参考文献', '參考文獻', '引用文献', '引用文獻', '参考资料', '參考資料',
        '参照文献', '文献', '文獻',
        '참고문헌', '참고\\s*문헌', '참조', '인용문헌',
        'références', 'bibliographie', 'ouvrages',
        'literatur', 'referenzen', 'quellen',
        'referencias', 'bibliografía', 'obras',
        'referências', 'bibliografia', 'riferimenti', 'opere',
        'литература', 'источники',
        'المراجع',
        'literatura', 'przypisy',
        'referenties', 'literatuurlijst', 'geciteerde',
        'referenser', 'litteraturförteckning', 'källförteckning',
        'referanser', 'litteraturliste', 'kildeliste',
        'referencer', 'kildefortegnelse',
        'lähteet', 'kirjallisuus', 'viitteet',
        'reference', 'seznam literatury',
        'kaynakça', 'referanslar', 'kaynaklar',
        'tài liệu tham khảo', 'tham khảo',
        'เอกสารอ้างอิง', 'บรรณานุกรม',
        'βιβλιογραφία', 'αναφορές',
        'ביבליוגרפיה', 'מראי',
        'irodalomjegyzék', 'hivatkozások', 'bibliográfia',
      ],
    ),
    BackMatterSectionDef(
      id: 'acknowledgments',
      label: '致谢',
      defaultIgnore: true,
      keywords: [
        'acknowledg',
        '致谢', '致謝', '謝辞', '謝辭', '谢辞', '谢辭',
        '감사', '사사',
        'remerciement', 'reconnaissance',
        'danksagung', '\\bdank',
        'agradecimiento', 'reconocimiento',
        'agradecimento', 'reconhecimento',
        'ringraziament',
        'благодарн', 'признат',
        'شكر', 'تقدير',
        'podziękowa',
        'dankbetuiging', 'dankwoord', 'erkenning',
        'erkännand', '\\btack', 'tacksägelse',
        'anerkjennelser', '\\btakk', 'takksigelser',
        'anerkendelser', '\\btak\\b', 'taksigelser',
        'kiitokset', 'kiitos',
        'poděkování',
        'teşekkür', 'bilgilendirme',
        'lời cảm ơn', 'cảm tạ',
        'ευχαριστ',
        'תודות', 'הכרת',
        'köszönet',
      ],
    ),
    BackMatterSectionDef(
      id: 'authors_contributions',
      label: '作者贡献/利益冲突',
      defaultIgnore: false,
      keywords: [
        'author', 'contributor', 'contribution',
        'compet', 'conflict', 'interest', 'declarations?',
        'disclos',
        '作者贡献', '作者貢獻', '著者貢', '执笔者', '執筆者',
        '利益冲突', '利益衝突', '竞争利益', '競爭利益', '竞争性利益',
        '利益声明', '利益聲明', '利益相關', '利益相关',
        '利益相反', '競合利益',
        '저자', '이해\\s*상충', '이해관계', '경쟁\\s*이익',
        'auteurs', 'intérêts', 'conflits',
        'autoren', 'beiträge', 'beitr', 'interessenkonflikt',
        'konkurrierende', 'offenlegung',
        'autores', 'contribuciones', 'intereses',
        'contribuições', 'interesses',
        'autori', 'contributi', 'contributo', 'interessi', 'conflitti',
        'вклад\\s+авторов', 'авторский', 'конфликт',
        'wkład', 'udział', 'konflikt',
        'auteursbijdragen', 'belangenconflicten', 'belangenverstrengeling',
        'concurrentiebelangen',
        'författarnas', 'författarbidrag', 'intressekonflikter', '\\bjäv\\b',
        'forfatterbidrag', 'forfatternes', 'interessekonflikter',
        'kirjoittajien', 'tekijöiden', 'eturistiriidat',
        'příspěvky', 'autorské', 'střet', 'prohlášení',
        'yazar', 'çıkar',
        'đóng góp', 'xung đột',
        'συνεισφορ', 'συμβολή', 'σύγκρουση',
        'תרומות', 'ניגוד',
        'szerzői', 'szerzők', 'összeférhetetlenség', 'érdekellentét',
      ],
    ),
    BackMatterSectionDef(
      id: 'funding_data',
      label: '资助/数据声明',
      defaultIgnore: false,
      keywords: [
        'funding', 'funder', 'grant', 'financial',
        'data\\s+(?:and\\s+|availability|sharing|access|management|deposition)',
        'data\\s+repository',
        'open\\s+data',
        'availability\\s+of\\s+data',
        '资金资助', '資金資助', '基金资助', '基金資助', '\\b资助', '\\b資助',
        '经费', '經費', '资金支持', '資金支持',
        '数据可用性', '資料可用性', '数据共享', '數據共享', '数据获取', '資料獲取',
        '資金提供', '資金援助', '助成', '研究費', '補助金',
        'データ可用性', 'データ入手', 'データ共有', 'データアクセス',
        '연구비', '재정', '자금', '데이터\\s*가용', '데이터\\s*이용', '데이터\\s*공유',
        'financement', 'subvention', 'soutien financier',
        'disponibilité', 'partage', 'accès aux',
        'finanzier', 'förderung', 'drittmittel',
        'datenverfügbarkeit', 'verfügbarkeit von daten', 'datenaustausch',
        'datenzugang',
        'financiación', 'financiamiento', 'apoyo financiero',
        'fuentes de financiación', 'subvencion',
        'disponibilidad de datos', 'acceso a datos', 'intercambio',
        'apoio financeiro', 'fontes de financiamento',
        'disponibilidade de dados', 'compartilhamento',
        'finanziament', 'supporto finanziario', 'fonti di finanziamento',
        'disponibilità dei dati', 'accesso ai dati', 'condivisione',
        'финансир', 'грант', 'финансовая поддержка',
        'доступность данных', 'обмен данными',
        'finansowanie', 'wsparcie finansowe', 'dotacj',
        'dostępność danych', 'udostępnianie',
        'financiering', 'subsidies', 'beschikbaarheid van gegevens',
        'databeschikbaarheid', 'gegevenstoegang',
        'finansiering', 'finansiellt stöd', 'finansieringskällor',
        'datatillgänglighet', 'tillgång till data', 'datadelning',
        'finansiell', 'finansieringskilder',
        'datatilgjengelighet', 'datatilgængelighed', 'tilgang til data',
        'rahoitus', 'taloudellinen tuki',
        'tietojen saatavuus', 'datan saatavuus',
        'financování', 'finanční podpora', 'zdroje financování', '\\bgranty',
        'dostupnost dat', 'sdílení dat',
        'finansman', 'finansal destek', 'fon kaynakları', 'hibe',
        'veri\\s+(?:erişilebilirliği|kullanılabilirliği|paylaşımı)',
        'tài trợ', 'nguồn tài trợ', 'hỗ trợ tài chính',
        'dữ liệu', 'truy cập dữ liệu',
        'χρηματοδότηση', 'πηγές χρηματοδότησης', 'οικονομική',
        'δεδομένων', 'πρόσβαση σε δεδομένα',
        'מימון', 'תמיכה כספית', 'זמינות נתונים', 'נגישות נתונים',
        'finanszírozás', 'támogatás', 'pénzügyi',
        'adatok elérhetősége', 'adatelérés',
      ],
    ),
    BackMatterSectionDef(
      id: 'supplementary_appendix',
      label: '附录/补充材料',
      defaultIgnore: false,
      keywords: [
        'supplement', 'supporting', 'additional', 'further',
        'append', 'annex',
        '补充', '補充', '附加', '辅助', '輔助', '额外', '額外',
        '附录', '附錄', '付録', '付录', '補足', '追加', 'その他の情報', '補遺',
        '보충', '추가', '부가', '기타', '부록',
        'complémentaire', 'supplémentaire', 'additionnel',
        'ergänz', 'zusätzlich', 'zusatzmaterial', 'ergänzungsmaterial',
        'weitere informationen', 'anhang',
        'complementaria', 'suplementario', 'suplementar',
        'adicional', 'apéndice', 'apêndice',
        'complementari', 'supplementare', 'aggiuntiv',
        'appendice',
        'дополнительн', 'вспомогательн', 'приложение',
        'uzupełniając', 'dodatkow', 'załącznik',
        'aanvullend', 'ondersteunend', 'extra informatie', 'bijlage',
        'kompletterande', 'stödinformation', 'ytterligare', '\\bbilaga',
        'tilleggs', 'støtteinformasjon', 'ytterligere',
        'supplerende', 'støtteinformation', 'yderligere',
        'täydentäv', 'lisämateriaali', 'tukitiedot', 'lisätied',
        'doplň', 'podpůrné', 'další informace', 'dodatečné', 'příloha',
        'ek\\s+bilgi', 'destekleyici', 'tamamlayıcı', 'ilave bilgi',
        'thông tin bổ', 'tài liệu bổ', 'dữ liệu bổ',
        'συμπληρωματικ', 'πρόσθετο', 'πρόσθετες',
        'משלים', 'מידע נוסף',
        'kiegészítő', 'támogató információk', 'további',
        'suplimentar', 'adiționale',
      ],
    ),
    BackMatterSectionDef(
      id: 'ethics_legends',
      label: '伦理声明/图表说明',
      defaultIgnore: false,
      keywords: [
        'ethic', 'institutional review', 'irb',
        'consent', 'human subject', 'animal\\s+(?:ethics|welfare|care)',
        'figure\\s+legend', 'table\\s+legend', 'figure\\s+caption',
        'table\\s+caption', 'list of figures', 'list of tables',
        'illustration', 'photo credits', 'image credits',
        '伦理', '倫理', '道德', '知情同意', '患者同意',
        '图例', '圖例', '表格说明', '表格說明', '图表说明', '圖表說明',
        '插图说明', '插圖說明',
        'インフォームドコンセント', '図の凡例', '表の凡例', '図表の説明',
        '윤리', '그림\\s*설명', '표\\s*설명', '도표\\s*설명',
        'éthique', 'consentement', 'légendes',
        'ethik', 'einwilligung', 'patienteneinwilligung',
        'abbildungslegenden', 'tabellenlegenden',
        'abbildungsverzeichnis', 'tabellenverzeichnis',
        'ética', 'consentimiento', 'leyendas',
        'consentimento', 'legendas',
        'etica', 'consenso', 'didascalie',
        'этическ', 'информированное согласие', 'подписи',
        'etyczn', 'zgoda', 'komisja etyczna',
        'ethische', 'geïnformeerde toestemming',
        'etikuttalande', 'etiskt godkännande', 'etisk kommitté',
        'etikkerklæring', 'etisk godkjenning', 'etisk komité',
        'etikerklæring', 'etisk godkendelse',
        'eettinen',
        'etické prohlášení', 'etické schválení', 'etická komise',
        'etik beyanı', 'etik onay', 'etik kurul', 'bilgilendirilmiş onam',
        'tuyên bố đạo đức', 'phê duyệt đạo đức',
        'δεοντολογ', 'ηθική',
        'אתיקה', 'אישור אתי',
        'etikai',
        'etică', 'aprobare etică',
      ],
    ),
  ];

  // ─── 公开 API ────────────────────────────────────────────────────────────

  /// app 启动时调一次。多次调用幂等。
  Future<void> init() async {
    if (_initialized) return;
    final raw = await rootBundle.loadString(
      'assets/config/back_matter_sections.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final levelPatterns = <_Level, List<String>>{
      _Level.l1: (data['l1']['patterns'] as List).cast<String>(),
      _Level.l2: (data['l2']['patterns'] as List).cast<String>(),
      _Level.l3: (data['l3']['patterns'] as List).cast<String>(),
    };

    // 反向归类：每个 pattern 按 keyword 子串匹配到首个 section
    final byIdLevel = <String, Map<_Level, List<String>>>{
      for (final s in availableSections)
        s.id: {_Level.l1: [], _Level.l2: [], _Level.l3: []},
    };
    for (final entry in levelPatterns.entries) {
      final level = entry.key;
      for (final pat in entry.value) {
        final id = _classifyPattern(pat);
        if (id == null) continue;
        byIdLevel[id]![level]!.add(pat);
      }
    }

    // 每个 section × level 拼成一个大正则，避免 N×regex 性能爆炸
    for (final section in availableSections) {
      final lvls = byIdLevel[section.id]!;
      _sectionRegexes[section.id] = _SectionRegexes(
        l1: _compileLevelRegex(lvls[_Level.l1]!),
        l2: _compileLevelRegex(lvls[_Level.l2]!),
        l3: _compileLevelRegex(lvls[_Level.l3]!),
      );
    }
    _initialized = true;
  }

  /// 按指定 section IDs 检测所有命中区域，按起始位置排序返回。
  /// 未 [init] 时返回空列表（safe-fail）。
  List<DetectedBackMatterSection> detectByIds({
    required String markdown,
    required Set<String> ids,
  }) {
    if (!_initialized || markdown.isEmpty || ids.isEmpty) return const [];
    final hits = <DetectedBackMatterSection>[];
    final halfPoint = (markdown.length * 0.5).floor();
    final latePoint = (markdown.length * 0.6).floor();

    for (final id in ids) {
      final regs = _sectionRegexes[id];
      if (regs == null) continue;
      _scanLevel(markdown, regs.l1, _Level.l1, id, 0, hits);
      _scanLevel(markdown, regs.l2, _Level.l2, id, halfPoint, hits);
      _scanLevel(markdown, regs.l3, _Level.l3, id, latePoint, hits);
    }
    hits.sort((a, b) => a.headingStart.compareTo(b.headingStart));
    return hits;
  }

  /// 检测**首个**命中的 back-matter 起始 offset（用于 markdown 截断）。
  /// 等同于 detectByIds 用全部 section 后取首条 headingStart。
  int? detectFirstOffset(String markdown) {
    final all = detectByIds(
      markdown: markdown,
      ids: availableSections.map((s) => s.id).toSet(),
    );
    return all.isEmpty ? null : all.first.headingStart;
  }

  // ─── 内部 ────────────────────────────────────────────────────────────────

  /// 按 keyword 子串匹配把 pattern 归类到一个 section（首匹配优先）。
  /// 顺序敏感：[availableSections] 中靠前的 section 优先抢匹配。
  static String? _classifyPattern(String pattern) {
    final lower = pattern.toLowerCase();
    for (final section in availableSections) {
      for (final kw in section.keywords) {
        // keyword 本身可能含 \\s 或 \\b 等正则字符，做一次 unescape 再 contains
        final plainKw = kw.replaceAll(r'\b', '').replaceAll(r'\s', ' ').trim();
        if (plainKw.isEmpty) continue;
        if (lower.contains(plainKw.toLowerCase())) return section.id;
      }
    }
    return null;
  }

  /// 把多条 pattern 拼成一个完整 heading 正则。null 表示无 patterns。
  static RegExp? _compileLevelRegex(List<String> patterns) {
    if (patterns.isEmpty) return null;
    // 与 document_summary_image_service 原有正则结构对齐：
    //   ^#{1,6} (可选编号 1.2.3) (PATTERN) (可选冒号/破折号尾) $
    final body = patterns.join('|');
    return RegExp(
      r'^\s*#{1,6}\s*(?:\d+(?:\.\d+)*[.)]?\s*)?(?:'
      '$body'
      r')\s*(?:[:：\-–—].*)?$',
      multiLine: true,
      caseSensitive: false,
      unicode: true,
    );
  }

  void _scanLevel(
    String markdown,
    RegExp? re,
    _Level level,
    String sectionId,
    int minStart,
    List<DetectedBackMatterSection> out,
  ) {
    if (re == null) return;
    for (final match in re.allMatches(markdown)) {
      if (match.start < minStart) continue;
      final range = _sectionContentRange(markdown, match.end);
      if (range == null) continue;
      out.add(DetectedBackMatterSection(
        id: sectionId,
        level: level.name,
        headingStart: match.start,
        contentStart: range.$1,
        contentEnd: range.$2,
      ));
    }
  }
}

class BackMatterSectionDef {
  final String id;
  final String label;
  final bool defaultIgnore;
  final List<String> keywords;
  const BackMatterSectionDef({
    required this.id,
    required this.label,
    required this.defaultIgnore,
    required this.keywords,
  });
}

class DetectedBackMatterSection {
  final String id;

  /// `'l1'` / `'l2'` / `'l3'`，对应原 JSON 置信度分级。
  final String level;
  final int headingStart;
  final int contentStart;
  final int contentEnd;
  const DetectedBackMatterSection({
    required this.id,
    required this.level,
    required this.headingStart,
    required this.contentStart,
    required this.contentEnd,
  });
}

enum _Level { l1, l2, l3 }

class _SectionRegexes {
  final RegExp? l1;
  final RegExp? l2;
  final RegExp? l3;
  const _SectionRegexes({this.l1, this.l2, this.l3});
}

// ─── 共享工具：从标题位置算 section 内容范围 ──────────────────────────────

(int, int)? _sectionContentRange(String markdown, int headingEnd) {
  int start = headingEnd;
  while (start < markdown.length && _isBlank(markdown.codeUnitAt(start))) {
    start++;
  }
  final after = markdown.substring(headingEnd);
  final next = _nextHeadingRe.firstMatch(after);
  int end = next != null ? headingEnd + next.start : markdown.length;
  while (end > start && _isBlank(markdown.codeUnitAt(end - 1))) {
    end--;
  }
  return start < end ? (start, end) : null;
}

bool _isBlank(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

final _nextHeadingRe = RegExp(r'^#{1,3}\s+\S', multiLine: true);
