/// 中文作者姓名拆分与合并工具。
///
/// 复姓列表来自 Jasminum（Zotero 中文文献插件），
/// 原始数据源：中国稀有姓氏统计小组。
class ChineseNameUtils {
  ChineseNameUtils._();

  // 按字符数降序排列，保证长复姓优先匹配
  static const compoundSurnames = [
    '奥屯', '百里', '比干', '单于',
    '陈留', '成公', '成功', '叱干', '褚师', '淳于',
    '达奚', '第二', '第五', '第伍', '第一', '丁若',
    '东方', '东里', '东门', '东野', '豆卢', '独孤', '端木', '段干',
    '尔朱',
    '伏羲', '状阳', '傅阳',
    '高堂', '高阳', '哥舒', '葛天',
    '公乘', '公上', '公孙', '公羊', '公冶', '共工', '古野', '关龙', '毌丘',
    '韩城', '贺兰', '贺楼', '贺若', '赫连', '呼延', '胡母', '胡毋', '斛律',
    '华原', '皇甫', '皇父',
    '可汗',
    '即墨', '夹谷', '揭阳',
    '令狐', '闾丘', '闾邱',
    '马服', '万矣', '墨台', '默台', '母丘', '木易', '慕容',
    '南宫', '南门', '女娲',
    '欧侯', '欧阳',
    '濮阳', '蒲察',
    '漆雕', '亓官', '綦连', '綦毋', '气伏', '青阳', '屈男', '屈突',
    '上官', '申徒', '申屠', '石抹', '士孙', '侍其', '水丘',
    '司城', '司空', '司寇', '司马', '司徒', '司星', '澹台',
    '拓跋', '太史', '太叔', '徒单', '涂山', '脱脱',
    '完颜', '闻人', '武城', '毋丘',
    '西门', '夏侯', '夏后', '鲜于', '相里', '轩辕',
    '延陵', '羊舌', '耶律', '宇文', '尉迟', '乐正',
    '宰父', '长孙', '钟离', '诸葛', '术虎', '主父', '祝融',
    '颛孙', '颛项', '子车', '宗正', '宗政',
    '邓李', '刘付', '陆费', '吴刘',
  ];

  static final _cjkRegExp = RegExp(r'[一-鿿㐀-䶿]');

  /// 判断名字是否包含 CJK 汉字
  static bool isChineseName(String name) => _cjkRegExp.hasMatch(name);

  /// 拆分中文全名为 {family, given}。
  ///
  /// 规则（与 Jasminum 一致）：
  /// 1. 含「·」→ 「·」前为姓，后为名（少数民族格式）
  /// 2. 以复姓开头 → 复姓为姓，余下为名
  /// 3. 默认 → 首字为姓，余下为名
  static ({String family, String given}) splitChineseName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return (family: '', given: '');

    // 少数民族：用「·」分隔
    if (trimmed.contains('·')) {
      final parts = trimmed.split('·');
      return (family: parts.first, given: parts.sublist(1).join('·'));
    }

    // 复姓匹配
    for (final surname in compoundSurnames) {
      if (trimmed.startsWith(surname) && trimmed.length > surname.length) {
        return (family: surname, given: trimmed.substring(surname.length));
      }
    }

    // 默认：首字为姓
    if (trimmed.length <= 1) return (family: trimmed, given: '');
    return (family: trimmed[0], given: trimmed.substring(1));
  }

  /// 将中文数据库返回的作者列表原始文本拆分为独立作者名。
  ///
  /// 支持分隔符：`; `（英文分号）、`；`（中文分号）、`，`（中文逗号）、`, `（英文逗号），
  /// 并自动去除尾部「等」。
  static List<String> parseAuthorList(String raw) {
    final cleaned = raw
        .replaceFirst(RegExp(r'[,，;；\s]*等\s*$'), '')
        .trim();
    if (cleaned.isEmpty) return [];

    return cleaned
        .split(RegExp(r'[;；]\s*|，\s*|,\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
