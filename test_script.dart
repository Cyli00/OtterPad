import 'dart:io';
import 'lib/utils/markdown_preprocessor.dart';

void main() {
  final text = '''
Abstract

Stage 1: image registration via phase correlation

Stage 2: ROI detection

\$\$
\\mathbf{A}_{ki} > 0, \\text{ if pixel } k \\text{ belongs to ROI } i
\\mathbf{A}_{ki} = 0, \\text{ otherwise }
\$\$

\$\$
\\mathbf{r}_k(t) = \\sum_i \\mathbf{A}_{ki} \\mathbf{f}_i(t) + \\sum_j \\mathbf{B}_{kj} \\mathbf{n}_j(t) + \\boldsymbol{\\eta}_k(t)
\$\$

Stage 3: ROI labelling and quality control

Stage 4: signal extraction and spike deconvolution
''';

  final result = MarkdownPreprocessor.process(text);
  print('--- RESULT ---');
  print(result);
}
