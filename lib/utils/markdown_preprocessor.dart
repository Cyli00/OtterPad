class MarkdownPreprocessor {
  /// 译文专用预处理：跳过块级公式提升和 $$...$$ 换行（会破坏 [[tr]] 标记）。
  static String processTranslation(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = result.replaceAllMapped(_inlineDollarRe, (match) {
      final trimmed = (match.group(1) ?? '').trim();
      return '\$$trimmed\$';
    });
    result = _simplifyInlineLatex(result);
    result = _normalizeInlineSpacing(result);
    return result;
  }

  static String process(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = _fixLatexSpacing(result);
    result = _promoteInlineEquations(result);
    result = _simplifyInlineLatex(result);
    result = _normalizeInlineSpacing(result);
    result = result.replaceAll(_emptyTableRe, '');
    result = _reflowParagraphs(result);
    return result;
  }

  /// 修复 OCR/版面解析残留的"异常段落切断"——PDF 多列、跨页、列内换行常被
  /// 错切成独立段落，破坏阅读连贯性。
  ///
  /// **合并策略**（保守优先）：
  /// - **跨双空行（真段落边界）合并**：仅当上段末**不是句末符** (`.!?。！？:;`)
  ///   时合并到下段；句末符是 OCR 文档中"真正段落结束"的最强信号，对它无条件
  ///   尊重——即使空行数异常也不动。
  /// - **段内多行（单 \n）合并**：默认 markdown 渲染会把单 \n 当软换行（CSS
  ///   `white-space: normal` 折叠为空格），但保留显式空格让翻译/搜索/复制更
  ///   干净；连字符断词（`evolu-\ntion` → `evolution`）特殊处理。
  /// - **中文无空格拼接**：CJK 字符之间不插空格，避免污染中文文本。
  /// - **跳过受保护行**：标题（`#`）、列表（`-`/`*`/`\d.`）、表格（`|`）、
  ///   figure（`![...](...)`）、blockquote（`>`）、HTML 块（`<`）、水平线，
  ///   以及代码块/数学块 fence 内全部内容——这些是结构性标记，不参与合并。
  ///
  /// **设计权衡**：宁可合并保守留下少量碎段，也不要错合并破坏真正段落。OCR
  /// 文档中"句末忘加句号"的场景极罕见，所以"非句末符 → 合并"的激进规则在
  /// 这个数据特征上几乎无误判风险。
  static String _reflowParagraphs(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    final pending = StringBuffer();
    bool inCodeFence = false;
    bool inMathFence = false;

    void emit() {
      if (pending.isEmpty) return;
      final paragraph = pending.toString();
      pending.clear();

      // 尝试与已 emit 的最后一段合并（跨空行场景）
      final lastIdx = _lastNonBlankIdx(out);
      if (lastIdx >= 0) {
        final merged = _tryMergeAcrossBlank(out[lastIdx], paragraph);
        if (merged != null) {
          out[lastIdx] = merged;
          // 移除中间所有空行（合并后空行不再有意义）
          while (out.length > lastIdx + 1) {
            out.removeLast();
          }
          return;
        }
      }
      out.add(paragraph);
    }

    for (final line in lines) {
      final trimmed = line.trim();

      // ─── Fence 边界与内部：原样保留 ───
      if (trimmed.startsWith('```')) {
        emit();
        out.add(line);
        inCodeFence = !inCodeFence;
        continue;
      }
      if (trimmed == r'$$') {
        emit();
        out.add(line);
        inMathFence = !inMathFence;
        continue;
      }
      if (inCodeFence || inMathFence) {
        emit();
        out.add(line);
        continue;
      }

      // ─── 空行：触发段落 emit，保留单空行作为段间分隔 ───
      if (trimmed.isEmpty) {
        if (pending.isNotEmpty) emit();
        out.add('');
        continue;
      }

      // ─── 受保护行：标题/列表/表格/figure/HTML 等独占段 ───
      if (_isProtectedLine(trimmed)) {
        emit();
        out.add(line);
        continue;
      }

      // ─── 普通文本行：拼到 pending（同段硬换行处理） ───
      if (pending.isEmpty) {
        pending.write(line);
      } else {
        final prev = pending.toString().trimRight();
        final curr = line.trimLeft();
        pending.clear();
        // 连字符断词（行末 `-` + 下行首小写英文）→ 直接拼
        if (prev.endsWith('-') &&
            curr.isNotEmpty &&
            RegExp(r'[a-z]').hasMatch(curr[0])) {
          pending.write(prev.substring(0, prev.length - 1));
          pending.write(curr);
        } else if (_endsWithChinese(prev) || _startsWithChinese(curr)) {
          // 中文场景：不插空格
          pending.write(prev);
          pending.write(curr);
        } else {
          pending.write(prev);
          pending.write(' ');
          pending.write(curr);
        }
      }
    }
    emit();

    // 多连空行 collapse 成单空行（合并后留下的孤立空行清理）
    return out.join('\n').replaceAll(_multiBlankRe, '\n\n');
  }

  /// 判断一行是否是"独占段"——markdown 结构性标记，不参与文本合并。
  static bool _isProtectedLine(String trimmed) {
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('#')) return true;
    if (_listItemRe.hasMatch(trimmed)) return true;
    if (trimmed.startsWith('|')) return true;
    if (_figureLineRe.hasMatch(trimmed)) return true;
    if (trimmed.startsWith('>')) return true;
    if (trimmed.startsWith('<')) return true;
    if (_horizontalRuleRe.hasMatch(trimmed)) return true;
    return false;
  }

  /// 跨空行段落合并判断：返回合并后字符串，null 表示保持分段。
  ///
  /// 核心规则：上段末是句末符（`.!?。！？:;`）→ 段落真的结束，不合并；
  /// 否则视为 OCR 错切，合并到下段。
  static String? _tryMergeAcrossBlank(String prev, String curr) {
    final prevEnd = prev.trimRight();
    final currStart = curr.trimLeft();
    if (prevEnd.isEmpty || currStart.isEmpty) return null;
    if (_isProtectedLine(prevEnd) || _isProtectedLine(currStart)) return null;

    final endChar = prevEnd[prevEnd.length - 1];
    final firstChar = currStart[0];

    // 连字符断词跨空行（罕见但保险）
    if (endChar == '-' && RegExp(r'[a-z]').hasMatch(firstChar)) {
      return prevEnd.substring(0, prevEnd.length - 1) + currStart;
    }

    // 中文：前末或后首是 CJK → 直接拼
    if (_isChineseChar(endChar) || _isChineseChar(firstChar)) {
      return prevEnd + currStart;
    }

    // 句末符 → 真段落边界，不合并
    if (_sentenceEndCharRe.hasMatch(endChar)) return null;

    // Unicode 上标结尾（作者行 affiliation / 脚注 / citation 编号）→ 段落结束，不合并
    if (_supCharRe.hasMatch(endChar)) return null;

    // 其他情况（逗号末/字母末/数字末/各种符号）→ 合并加空格
    return '$prevEnd $currStart';
  }

  static bool _isChineseChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    // CJK Unified Ideographs + Extension A + CJK Symbols and Punctuation
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x3000 && code <= 0x303F) ||
        (code >= 0xFF00 && code <= 0xFFEF); // 全角符号/标点
  }

  static bool _endsWithChinese(String s) =>
      s.isNotEmpty && _isChineseChar(s[s.length - 1]);

  static bool _startsWithChinese(String s) =>
      s.isNotEmpty && _isChineseChar(s[0]);

  static int _lastNonBlankIdx(List<String> lines) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim().isNotEmpty) return i;
    }
    return -1;
  }

  /// 通过元数据标题匹配，过滤 Markdown 中标题行之前的冗余内容（如期刊名）。
  ///
  /// 例如提取结果为：
  /// ```
  /// # Cell Metabolism
  /// # Microglial lipid droplet accumulation in tauopathy brain...
  /// ```
  /// 传入 title="Microglial lipid droplet accumulation..."，
  /// 则会删除 "# Cell Metabolism" 及其之前的所有内容。
  static String filterBeforeTitle(String markdown, String? title) {
    if (title == null || title.trim().isEmpty) return markdown;

    final lines = markdown.split('\n');
    int titleLineIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#')) continue;

      final headingText = line.replaceFirst(_headingPrefixRe, '').trim();
      if (_isMatchingTitle(headingText, title.trim())) {
        titleLineIndex = i;
        break;
      }
    }

    if (titleLineIndex <= 0) return markdown;

    return lines.sublist(titleLineIndex).join('\n');
  }

  static bool _isMatchingTitle(String heading, String title) {
    final h = heading.toLowerCase().replaceAll(_wsRunRe, ' ');
    final t = title.toLowerCase().replaceAll(_wsRunRe, ' ');

    if (h == t) return true;
    if (h.contains(t) || t.contains(h)) return true;

    // 词汇重叠度 >= 80%（忽略短词）
    final titleWords = t.split(' ').where((w) => w.length > 2).toSet();
    if (titleWords.isEmpty) return false;
    final headingWords = h.split(' ').toSet();
    final overlap = titleWords.intersection(headingWords).length;
    return overlap / titleWords.length >= 0.8;
  }

  /// 将独占一行的长内联公式（$...$）提升为块级公式（$$...$$）。
  /// API 提取经常将独立的 display 方程误标为 inline。
  static String _promoteInlineEquations(String text) {
    return text.replaceAllMapped(_loneInlineEqRe, (match) {
      final inner = (match.group(1) ?? '').trim();
      if (inner.contains('=') || inner.length > 60) {
        return '\n\$\$\n$inner\n\$\$\n';
      }
      return match.group(0) ?? '';
    });
  }

  static String _sanitizeLatex(String text) {
    // `\boldsymbol{\boldsymbol{...}}` 的递归扁平化已由 `_stripFontWrappers` 覆盖，
    // 此处只做不可并入那一步的修正（pmb/mbox 别名、array 列规范）。
    var res = text
        .replaceAll(_pmbRe, r'\boldsymbol')
        .replaceAll(_mboxRe, r'\text');
    res = res.replaceAllMapped(
      _arrayColsRe,
      (m) =>
          r'\begin{array}{'
          '${(m.group(1) ?? '').replaceAll(' ', '')}'
          '}',
    );
    return res;
  }

  static String _fixLatexSpacing(String text) {
    var res = text.replaceAllMapped(_inlineDollarRe, (match) {
      final trimmed = (match.group(1) ?? '').trim();
      return '\$$trimmed\$';
    });

    res = res.replaceAllMapped(_blockDollarLineRe, (match) {
      final inner = match.group(1)?.trim() ?? '';
      return '\n\$\$\n$inner\n\$\$\n';
    });

    res = res.replaceAllMapped(_blockDollarRe, (match) {
      final inner = match.group(1)?.trim() ?? '';
      return '\n\$\$\n$inner\n\$\$\n';
    });

    return res;
  }

  /// 尝试将每段内联 `$...$` 降级为 Unicode 纯文本（可被 SelectionArea 选中）。
  /// 任一步无法完全解析（含未识别的 `\xxx`、残留的 `{}` 或 `^` `_`），
  /// 则保留原始 `$...$` 交给 `Math.tex` 渲染。
  static String _simplifyInlineLatex(String text) {
    return text.replaceAllMapped(_inlineDollarRe, (match) {
      final inner = (match.group(1) ?? '').trim();

      final plainTextMatch = _plainTextCmdRe.firstMatch(inner);
      if (plainTextMatch != null) {
        return (plainTextMatch.group(1) ?? '')
            .replaceAllMapped(_textCmdNestedRe, (nested) => nested.group(1) ?? '');
      }

      final bareSuperscriptMatch = _bareSuperscriptRe.firstMatch(inner);
      if (bareSuperscriptMatch != null) {
        final sup =
            _toScriptStrict(bareSuperscriptMatch.group(1) ?? '', _superscriptMap);
        if (sup != null) return sup;
      }

      final resolved = _tryResolveLatexToUnicode(inner);
      if (resolved != null) return resolved;

      return '\$$inner\$';
    });
  }

  /// 通用 LaTeX → Unicode 尝试。仅当结果不再含 `\`、`{`、`}`、`^`、`_` 时返回。
  static String? _tryResolveLatexToUnicode(String inner) {
    // 纯文本短路：不含任何可解析符号，无需走 pipeline。
    if (!_needsResolutionRe.hasMatch(inner)) return inner;

    var s = _stripFontWrappers(inner);
    s = _substituteLatexMacros(s);
    s = _resolveInlineScripts(s);
    s = s.replaceAll(_emptyBracesRe, '');
    if (_residualLatexRe.hasMatch(s)) return null;
    return s;
  }

  static String _stripFontWrappers(String s) {
    var result = s;
    for (final re in _fontWrapperPatterns) {
      for (var i = 0; i < 3; i++) {
        final prev = result;
        result = result.replaceAllMapped(re, (m) => m.group(1) ?? '');
        if (prev == result) break;
      }
    }
    return result;
  }

  static String _substituteLatexMacros(String s) {
    var result = s;
    for (final entry in _sortedLatexMacros) {
      result = result.replaceAll(entry.$1, entry.$2);
    }
    return result;
  }

  static String _resolveInlineScripts(String s) {
    var result = s;
    result = result.replaceAllMapped(_supBracedRe, (m) {
      final sup = _toScriptStrict(m.group(1) ?? '', _superscriptMap);
      return sup ?? m.group(0) ?? '';
    });
    result = result.replaceAllMapped(_subBracedRe, (m) {
      final sub = _toScriptStrict(m.group(1) ?? '', _subscriptMap);
      return sub ?? m.group(0) ?? '';
    });
    result = result.replaceAllMapped(_supSingleRe, (m) {
      final sup = _toScriptStrict(m.group(1) ?? '', _superscriptMap);
      return sup ?? m.group(0) ?? '';
    });
    result = result.replaceAllMapped(_subSingleRe, (m) {
      final sub = _toScriptStrict(m.group(1) ?? '', _subscriptMap);
      return sub ?? m.group(0) ?? '';
    });
    return result;
  }

  /// 严格模式：任一字符无对应 Unicode 上/下标形式即返回 null。
  static String? _toScriptStrict(String text, Map<String, String> map) {
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == ' ') {
        buf.write(' ');
        continue;
      }
      final mapped = map[ch];
      if (mapped == null) return null;
      buf.write(mapped);
    }
    return buf.toString();
  }

  static String _normalizeInlineSpacing(String text) {
    var result = text.replaceAllMapped(
      _supBeforeRe,
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      _supAfterRe,
      (match) => '${match.group(1)}${match.group(2)}',
    );
    return result;
  }
}

// ─── 预编译的库级 RegExp（避免每次调用重新编译）───

final RegExp _emptyTableRe = RegExp(r'<table[^>]*>\s*</table>');
final RegExp _headingPrefixRe = RegExp(r'^#+\s*');
final RegExp _wsRunRe = RegExp(r'\s+');

// _reflowParagraphs 辅助
final RegExp _multiBlankRe = RegExp(r'\n{3,}');
final RegExp _listItemRe = RegExp(r'^([-*+]|\d+[.)])\s');
/// 匹配独占一行的 markdown 图片. alt 部分用贪婪 `.*` 而非 `[^\]]*`,
/// 因为 figure caption 内随处可见**平衡的方括号** (`[Cont]`, `[KA1D]`,
/// `[Color figure can be viewed at wileyonlinelibrary.com]` 等),
/// `[^\]]*` 会在首个 `]` 处过早断裂导致整行匹配失败 → `_isProtectedLine`
/// 返回 false → `_reflowParagraphs` 把 imgTag 当成正文合并进相邻段落.
/// 贪婪 `.*` 让正则引擎从末尾 backtrack 找最后一个 `]\(...\)` 边界,
/// 平衡 / 不平衡的内嵌方括号都能命中.
final RegExp _figureLineRe = RegExp(r'^!\[.*\]\(.*\)\s*$');
final RegExp _horizontalRuleRe = RegExp(r'^[-*_]{3,}\s*$');
final RegExp _sentenceEndCharRe = RegExp(r'[.!?。！？:;]');

/// 末字符是否为 Unicode 上标（字符集与 [_supBeforeRe] 保持同步）。
/// 命中即视为段落终止信号——作者行末 affiliation 数字、脚注 / citation 引用都属此类。
final RegExp _supCharRe = RegExp(
  r'^[⁰-⁹¹²³⁺-ⁿⁱ'
  r'ᴬ-ᵪᵸᶛ-ᶿʰ-ʸˠ-ˤⱽ]$',
);

final RegExp _loneInlineEqRe =
    RegExp(r'^[ \t]*\$([^\$\n]+)\$[ \t]*$', multiLine: true);

final RegExp _pmbRe = RegExp(r'\\pmb(?=\s*\{)');
final RegExp _mboxRe = RegExp(r'\\mbox(?=\s*\{)');
final RegExp _arrayColsRe =
    RegExp(r'\\begin\{array\}\{([rclp|]+(?:\s+[rclp|]+)+)\}');

final RegExp _inlineDollarRe = RegExp(r'\$([^\$\n]+)\$');
final RegExp _blockDollarLineRe = RegExp(
  r'^[ \t]*\$\$[ \t]*$(.*?)^[ \t]*\$\$[ \t]*$',
  multiLine: true,
  dotAll: true,
);
final RegExp _blockDollarRe = RegExp(r'\$\$(.*?)\$\$');

final RegExp _plainTextCmdRe = RegExp(
  r'^\\(?:underline|text|textrm|texttt|textsf|textbf)\{((?:[^{}]|\{[^{}]*\})+)\}$',
);
final RegExp _textCmdNestedRe = RegExp(r'\\text\{([^{}]+)\}');
final RegExp _bareSuperscriptRe = RegExp(r'^\{\}\s*\^\{([^{}]+)\}$');

/// 纯文本快筛：含下列任一字符才需要走 macro/scripts 解析。
final RegExp _needsResolutionRe = RegExp(r'[\\{}^_]');

/// 解析后剩余的 LaTeX 残骸——含即视为解析失败。
final RegExp _residualLatexRe = RegExp(r'[\\{}^_]');

final RegExp _emptyBracesRe = RegExp(r'\{\s*\}');

final RegExp _supBracedRe = RegExp(r'\^\{([^{}^_]+)\}');
final RegExp _subBracedRe = RegExp(r'_\{([^{}^_]+)\}');
final RegExp _supSingleRe = RegExp(r'\^([^\s{}^_\\])');
final RegExp _subSingleRe = RegExp(r'_([^\s{}^_\\])');

/// 上/下标字符集合——用于清理上标边上的多余空格。
/// 与 [_superscriptMap] 的 value 集合保持同步。
final RegExp _supBeforeRe = RegExp(
  r'(?<=\S)\s+([\u2070-\u2079\u00B9\u00B2\u00B3\u207A-\u207F\u2071'
  r'\u1D2C-\u1D6A\u1D78\u1D9B-\u1DBF\u02B0-\u02B8\u02E0-\u02E4\u2C7D]+)',
);
final RegExp _supAfterRe = RegExp(
  r'([\u2070-\u2079\u00B9\u00B2\u00B3\u207A-\u207F\u2071'
  r'\u1D2C-\u1D6A\u1D78\u1D9B-\u1DBF\u02B0-\u02B8\u02E0-\u02E4\u2C7D]+)'
  r'\s+([.,;:!?])',
);

/// 预编译的字体包装 pattern（\mathrm{...} → ... 等）。
final List<RegExp> _fontWrapperPatterns = [
  'mathrm', 'mathbf', 'mathit', 'mathsf', 'mathtt',
  'mathsc', 'mathbb', 'mathcal', 'boldsymbol',
].map((c) => RegExp('\\\\$c\\{([^{}]+)\\}')).toList(growable: false);

/// 预编译的 macro 替换表：(边界感知 RegExp, Unicode)。按 key 长度倒序，
/// 防止 `\e` 在 `\epsilon` 之前匹配吞掉它。
final List<(RegExp, String)> _sortedLatexMacros = (() {
  final needsBoundary = RegExp(r'[a-zA-Z]$');
  final keys = _latexSymbolMap.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return keys.map((k) {
    final esc = RegExp.escape(k);
    // 以字母结尾的宏名后面不能跟另一个字母，否则是另一个宏的前缀。
    final re = k.startsWith(r'\') && needsBoundary.hasMatch(k)
        ? RegExp('$esc(?![a-zA-Z])')
        : RegExp(esc);
    return (re, _latexSymbolMap[k]!);
  }).toList(growable: false);
})();

// ─── LaTeX 宏 / Unicode 映射表 ───

const Map<String, String> _latexSymbolMap = {
  // 小写希腊字母
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
  r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ',
  r'\omicron': 'ο', r'\pi': 'π', r'\varpi': 'ϖ', r'\rho': 'ρ',
  r'\varrho': 'ϱ', r'\sigma': 'σ', r'\varsigma': 'ς', r'\tau': 'τ',
  r'\upsilon': 'υ', r'\phi': 'φ', r'\varphi': 'ϕ', r'\chi': 'χ',
  r'\psi': 'ψ', r'\omega': 'ω',
  // 大写希腊字母
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ',
  r'\Phi': 'Φ', r'\Psi': 'Ψ', r'\Omega': 'Ω',
  // 关系 / 运算符
  r'\approx': '≈', r'\sim': '∼', r'\simeq': '≃', r'\cong': '≅',
  r'\equiv': '≡', r'\propto': '∝',
  r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\ast': '∗',
  r'\pm': '±', r'\mp': '∓',
  r'\leq': '≤', r'\le': '≤', r'\geq': '≥', r'\ge': '≥',
  r'\neq': '≠', r'\ne': '≠', r'\ll': '≪', r'\gg': '≫',
  r'\in': '∈', r'\notin': '∉', r'\ni': '∋',
  r'\subset': '⊂', r'\supset': '⊃',
  r'\subseteq': '⊆', r'\supseteq': '⊇',
  r'\cup': '∪', r'\cap': '∩', r'\emptyset': '∅',
  // 箭头
  r'\to': '→', r'\rightarrow': '→', r'\leftarrow': '←',
  r'\Rightarrow': '⇒', r'\Leftarrow': '⇐',
  r'\leftrightarrow': '↔', r'\Leftrightarrow': '⇔',
  r'\uparrow': '↑', r'\downarrow': '↓',
  r'\mapsto': '↦',
  // 标点 / 括号
  r'\langle': '⟨', r'\rangle': '⟩',
  r'\lceil': '⌈', r'\rceil': '⌉',
  r'\lfloor': '⌊', r'\rfloor': '⌋',
  r'\cdots': '⋯', r'\ldots': '…', r'\dots': '…', r'\vdots': '⋮',
  // 逻辑 / 量词
  r'\forall': '∀', r'\exists': '∃', r'\neg': '¬',
  r'\wedge': '∧', r'\vee': '∨',
  // 分析
  r'\partial': '∂', r'\nabla': '∇', r'\infty': '∞',
  r'\sum': '∑', r'\prod': '∏', r'\int': '∫',
  r'\sqrt': '√',
  // 角度
  r'\circ': '∘', r'\degree': '°',
  // 转义字符
  r'\%': '%', r'\&': '&', r'\#': '#', r'\$': r'$',
  r'\_': '_', r'\{': '{', r'\}': '}',
  // 间距（全部当作单空格或空）
  r'\,': ' ', r'\;': ' ', r'\:': ' ', r'\!': '', r'\ ': ' ',
  r'\quad': '  ', r'\qquad': '    ',
  // 空操作
  r'\left': '', r'\right': '', r'\displaystyle': '',
  r'\textstyle': '', r'\scriptstyle': '',
};

/// 可 Unicode 化的上标字符映射（严格模式依据）。
const Map<String, String> _superscriptMap = {
  // 数字
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  // 符号
  '+': '⁺', '-': '⁻', '−': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  '.': '·', ',': '˒',
  // 小写拉丁字母（q 无标准 Unicode 上标形式）
  'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ',
  'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
  'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ',
  'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
  'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
  // 大写拉丁字母（C/F/Q/S/X/Y/Z 无标准上标）
  'A': 'ᴬ', 'B': 'ᴮ', 'D': 'ᴰ', 'E': 'ᴱ', 'G': 'ᴳ',
  'H': 'ᴴ', 'I': 'ᴵ', 'J': 'ᴶ', 'K': 'ᴷ', 'L': 'ᴸ',
  'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ', 'P': 'ᴾ', 'R': 'ᴿ',
  'T': 'ᵀ', 'U': 'ᵁ', 'V': 'ⱽ', 'W': 'ᵂ',
  // 部分希腊字母
  'α': 'ᵅ', 'β': 'ᵝ', 'γ': 'ᵞ', 'δ': 'ᵟ', 'ε': 'ᵋ',
  'θ': 'ᶿ', 'ι': 'ᶥ', 'φ': 'ᵠ', 'ϕ': 'ᶲ', 'χ': 'ᵡ',
};

/// 可 Unicode 化的下标字符映射。
const Map<String, String> _subscriptMap = {
  // 数字
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  // 符号
  '+': '₊', '-': '₋', '−': '₋', '=': '₌', '(': '₍', ')': '₎',
  // 小写拉丁字母（仅部分有 Unicode 下标）
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
  'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
  'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
  'v': 'ᵥ', 'x': 'ₓ',
  // 部分希腊字母
  'β': 'ᵦ', 'γ': 'ᵧ', 'ρ': 'ᵨ', 'ϕ': 'ᵩ', 'χ': 'ᵪ',
};
