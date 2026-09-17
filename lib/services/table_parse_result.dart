import 'dart:convert';
import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// 只转换 OCR 已有内容，不推断表头、补全数值或重新识别图片。
class TableCell {
  final int row, column, rowSpan, columnSpan;
  final String text;
  final bool header;

  const TableCell({
    required this.row,
    required this.column,
    required this.text,
    this.rowSpan = 1,
    this.columnSpan = 1,
    this.header = false,
  });
}

class TableParseResult {
  final int rowCount, columnCount;
  final List<TableCell> cells;

  const TableParseResult({
    required this.rowCount,
    required this.columnCount,
    required this.cells,
  });

  static String plainText(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is dom.Element) {
      if (const {
        'script',
        'style',
        'iframe',
        'object',
      }.contains(node.localName)) {
        return '';
      }
      if (node.localName == 'br') return '\n';
    }
    final text = node.nodes.map(plainText).join();
    return node is dom.Element &&
            const {'p', 'div', 'li'}.contains(node.localName)
        ? '$text\n'
        : text;
  }

  static dom.Element? _parentTable(dom.Element element) {
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == 'table') return parent;
      parent = parent.parent;
    }
    return null;
  }

  static List<TableParseResult> fromHtml(String content) {
    final document = html.parseFragment(content);
    return [
      for (final table in document.querySelectorAll('table'))
        if (_parentTable(table) == null) _fromElement(table),
    ];
  }

  static TableParseResult _fromElement(dom.Element table) {
    final rows = table
        .querySelectorAll('tr')
        .where((row) => _parentTable(row) == table)
        .toList();
    if (rows.isEmpty || rows.length > 10000) {
      throw const FormatException('table_size');
    }
    final occupied = <(int, int)>{};
    final cells = <TableCell>[];
    var columns = 0;
    for (var r = 0; r < rows.length; r++) {
      var c = 0;
      for (final element in rows[r].children.where(
        (e) => e.localName == 'td' || e.localName == 'th',
      )) {
        while (occupied.contains((r, c))) {
          c++;
        }
        int span(String key) {
          final value = element.attributes[key];
          if (value == null) return 1;
          final parsed = int.tryParse(value);
          // HTML rowspan=0 表示延伸至当前行组末尾。
          if (key == 'rowspan' && parsed == 0) {
            var end = r + 1;
            while (end < rows.length && rows[end].parent == rows[r].parent) {
              end++;
            }
            return end - r;
          }
          if (parsed == null || parsed < 1 || parsed > 1000) {
            throw const FormatException('table_span');
          }
          return parsed;
        }

        final rs = span('rowspan'), cs = span('colspan');
        if (r + rs > rows.length ||
            c + cs > 1000 ||
            (r + rs) * (c + cs) > 100000) {
          throw const FormatException('table_size');
        }
        for (var rr = r; rr < r + rs; rr++) {
          for (var cc = c; cc < c + cs; cc++) {
            if (!occupied.add((rr, cc))) {
              throw const FormatException('table_overlap');
            }
          }
        }
        cells.add(
          TableCell(
            row: r,
            column: c,
            text: plainText(element).trim(),
            rowSpan: rs,
            columnSpan: cs,
            header: element.localName == 'th',
          ),
        );
        c += cs;
        columns = math.max(columns, c);
      }
    }
    if (columns == 0 || rows.length * columns > 100000) {
      throw const FormatException('table_size');
    }
    return TableParseResult(
      rowCount: rows.length,
      columnCount: columns,
      cells: cells,
    );
  }

  static TableParseResult? fromMarkdown(String content) {
    final lines = const LineSplitter().convert(content.trim());
    List<String> split(String line) {
      var value = line.trim();
      if (value.startsWith('|')) value = value.substring(1);
      if (value.endsWith('|') && !value.endsWith(r'\|')) {
        value = value.substring(0, value.length - 1);
      }
      return value
          .split(RegExp(r'(?<!\\)\|'))
          .map((s) => s.trim().replaceAll(r'\|', '|'))
          .toList();
    }

    if (lines.length < 2 || !lines.first.contains('|')) return null;
    final separator = split(lines[1]);
    if (separator.isEmpty ||
        !separator.every((s) => RegExp(r'^:?-{3,}:?$').hasMatch(s))) {
      return null;
    }
    final rows = [split(lines.first), ...lines.skip(2).map(split)];
    if (rows.any((row) => row.length != separator.length) ||
        rows.length * separator.length > 100000) {
      return null;
    }
    return TableParseResult(
      rowCount: rows.length,
      columnCount: separator.length,
      cells: [
        for (var r = 0; r < rows.length; r++)
          for (var c = 0; c < separator.length; c++)
            TableCell(row: r, column: c, text: rows[r][c], header: r == 0),
      ],
    );
  }

  List<List<String>> get grid {
    final rows = List.generate(rowCount, (_) => List.filled(columnCount, ''));
    for (final cell in cells) {
      rows[cell.row][cell.column] = cell.text;
    }
    return rows;
  }

  String get tsv => grid
      .map(
        (row) => row
            .map(
              (text) => text.contains(RegExp('[\t\r\n"]'))
                  ? '"${text.replaceAll('"', '""')}"'
                  : text,
            )
            .join('\t'),
      )
      .join('\n');

  String get markdown {
    final rows = grid
        .map(
          (row) =>
              '| ${row.map((text) => text.replaceAll('\\', '\\\\').replaceAll('|', r'\|').replaceAll(RegExp(r'\r?\n'), '<br>')).join(' | ')} |',
        )
        .toList();
    rows.insert(1, '| ${List.filled(columnCount, '---').join(' | ')} |');
    return rows.join('\n');
  }

  String get htmlText {
    const escape = HtmlEscape();
    final out = StringBuffer('<table><tbody>');
    for (var row = 0; row < rowCount; row++) {
      out.write('<tr>');
      var column = 0;
      for (final cell in cells.where((c) => c.row == row)) {
        // 不完整 OCR 行的空缺保留为空，不移动其后单元格。
        while (column < cell.column) {
          if (!cells.any(
            (c) =>
                c.row < row &&
                c.row + c.rowSpan > row &&
                c.column <= column &&
                c.column + c.columnSpan > column,
          )) {
            out.write('<td></td>');
          }
          column++;
        }
        final tag = cell.header ? 'th' : 'td';
        out.write(
          '<$tag rowspan="${cell.rowSpan}" colspan="${cell.columnSpan}">'
          '${escape.convert(cell.text).replaceAll('\n', '<br>')}</$tag>',
        );
        column = cell.column + cell.columnSpan;
      }
      out.write('</tr>');
    }
    out.write('</tbody></table>');
    return out.toString();
  }
}
