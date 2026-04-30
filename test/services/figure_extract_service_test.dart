import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/figure_extract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  test('连续底部图注不会把后一张图吸到前一张', () {
    final service = FigureExtractService.instance;
    final blocks = [
      _block('1', 'figure_title', [320, 91, 345, 110], '(a)'),
      _block('2', 'chart', [307, 100, 665, 439]),
      _block('3', 'figure_title', [688, 89, 712, 109], '(b)'),
      _block('4', 'chart', [674, 108, 1036, 436]),
      _block('5', 'figure_title', [
        305,
        459,
        1106,
        625,
      ], 'Figure 6. Size correlations.'),
      _block('6', 'figure_title', [309, 656, 335, 678], '(a)'),
      _block('7', 'figure_title', [670, 656, 697, 679], '(b)'),
      _block('8', 'image', [309, 674, 664, 1008]),
      _block('9', 'chart', [665, 661, 1031, 788]),
      _block('10', 'chart', [673, 806, 1033, 1031]),
      _block('11', 'figure_title', [
        305,
        1052,
        1082,
        1095,
      ], 'Figure 7. Average fluorescence recording.'),
      _block('12', 'table', [310, 1130, 1099, 1338]),
      _block('13', 'figure_title', [
        307,
        1353,
        699,
        1376,
      ], 'Table 1. Information about the analyzed recordings.'),
    ];

    final segments = service.findFigureSegments(blocks);

    expect(_idsForCaption(segments, 'Figure 6'), ['5', '1', '2', '3', '4']);
    expect(_idsForCaption(segments, 'Figure 7'), [
      '11',
      '6',
      '7',
      '8',
      '9',
      '10',
    ]);
    expect(_idsForCaption(segments, 'Table 1'), ['13', '12']);
  });
}

LayoutBlock _block(
  String id,
  String label,
  List<double> bbox, [
  String content = '',
]) {
  return LayoutBlock(
    blockId: id,
    blockLabel: label,
    blockBbox: bbox,
    blockContent: content,
  );
}

List<String> _idsForCaption(
  List<List<LayoutBlock>> segments,
  String captionPrefix,
) {
  final segment = segments.singleWhere(
    (segment) =>
        segment.any((block) => block.blockContent.startsWith(captionPrefix)),
  );
  return segment.map((block) => block.blockId).toList();
}
