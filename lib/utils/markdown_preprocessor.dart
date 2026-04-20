class MarkdownPreprocessor {
  static String process(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = _fixLatexSpacing(result);
    result = _promoteInlineEquations(result);
    result = _simplifyInlineLatex(result);
    result = _normalizeInlineSpacing(result);
    result = result.replaceAll(_emptyTableRe, '');
    return result;
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
      final inner = match.group(1)!.trim();
      if (inner.contains('=') || inner.length > 60) {
        return '\n\$\$\n$inner\n\$\$\n';
      }
      return match.group(0)!;
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
          '${m.group(1)!.replaceAll(' ', '')}'
          '}',
    );
    return res;
  }

  static String _fixLatexSpacing(String text) {
    var res = text.replaceAllMapped(_inlineDollarRe, (match) {
      final trimmed = match.group(1)!.trim();
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
      final inner = match.group(1)!.trim();

      final plainTextMatch = _plainTextCmdRe.firstMatch(inner);
      if (plainTextMatch != null) {
        return plainTextMatch
            .group(1)!
            .replaceAllMapped(_textCmdNestedRe, (nested) => nested.group(1)!);
      }

      final bareSuperscriptMatch = _bareSuperscriptRe.firstMatch(inner);
      if (bareSuperscriptMatch != null) {
        final sup =
            _toScriptStrict(bareSuperscriptMatch.group(1)!, _superscriptMap);
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
        result = result.replaceAllMapped(re, (m) => m.group(1)!);
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
      final sup = _toScriptStrict(m.group(1)!, _superscriptMap);
      return sup ?? m.group(0)!;
    });
    result = result.replaceAllMapped(_subBracedRe, (m) {
      final sub = _toScriptStrict(m.group(1)!, _subscriptMap);
      return sub ?? m.group(0)!;
    });
    result = result.replaceAllMapped(_supSingleRe, (m) {
      final sup = _toScriptStrict(m.group(1)!, _superscriptMap);
      return sup ?? m.group(0)!;
    });
    result = result.replaceAllMapped(_subSingleRe, (m) {
      final sub = _toScriptStrict(m.group(1)!, _subscriptMap);
      return sub ?? m.group(0)!;
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
      (match) => match.group(1)!,
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
