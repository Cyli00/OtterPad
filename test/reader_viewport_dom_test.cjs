const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-viewport-'));
const asset = name => fs.readFileSync(path.join(root, 'assets/reader', name), 'utf8');
const paragraphs = Array.from({length: 50}, (_, i) =>
  `<p data-paragraph-id="p${i}" data-language="source">Paragraph ${i}. ${'Reader viewport text. '.repeat(25)}</p>`).join('');
const assertions = `
const check = (condition, message) => { if (!condition) throw Error(message); };
const settle = () => new Promise(resolve => setTimeout(resolve, 150));
window.addEventListener('load', async () => {
  try {
    await settle();
    const content = document.getElementById('content');
    const original = [...content.querySelectorAll('p')];
    const physicalWidth = innerWidth;
    readerSetViewportWidth(900);
    original[12].scrollIntoView();
    await settle();
    for (const width of [540, 780, 440, 900]) {
      const anchor = content.children[_findAnchorBlockIndex()];
      const top = anchor.getBoundingClientRect().top;
      readerSetViewportWidth(width);
      check(Math.abs(anchor.getBoundingClientRect().top - top) < 2, '正文宽度变化保持当前段落位置');
      check(document.body.getBoundingClientRect().width === width, '正文使用可见宽度');
      check(innerWidth === physicalWidth, '原生画布宽度没有变化');
      await settle();
      check(Math.abs(anchor.getBoundingClientRect().top - top) < 2, '后续帧不二次跳动');
    }
    check(original.every((p, i) => p === content.querySelectorAll('p')[i]), '正文节点没有重建');
    readerSetViewportWidth(NaN); readerSetViewportWidth(0); readerSetViewportWidth(-1);
    check(readerViewportWidth() === 900, '忽略无效宽度');

    window.scrollTo(0, 0);
    document.body.dataset.desktop = 'false';
    setPaginationMode('horizontal');
    await settle();
    readerSetViewportWidth(600);
    _restoreToAnchor(12);
    await settle();
    check(content.scrollLeft > 0, '横向模式可定位正文 ' + [content.scrollWidth, content.clientWidth, content.clientHeight, getComputedStyle(content).columnWidth]);
    check(Math.abs(content.scrollLeft / 600 - Math.round(content.scrollLeft / 600)) < .01, '横向翻页使用正文宽度');
    const anchor = _findAnchorBlockIndex();
    readerSetViewportWidth(800);
    check(Math.abs(content.scrollLeft / 800 - Math.round(content.scrollLeft / 800)) < .01, '重新变宽后仍按整页定位');
    const rects = [...content.children[anchor].getClientRects()];
    check(rects.some(r => r.right > 0 && r.left < 800), '横向变宽后原段落仍可见');
    check(Math.abs(document.getElementById('page-footer').getBoundingClientRect().left + document.getElementById('page-footer').getBoundingClientRect().width / 2 - 400) < 1, '页码居中于可见正文');
    document.body.dataset.result = 'PASS';
  } catch (error) { document.body.dataset.result = 'FAIL: ' + error.message; }
});
`;
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
:root {--font-size:18px;--line-height:1.7;--block-margin:1;--bg:white;--text:black;--secondary:gray;--font-family:serif;--top-inset:20px;--bottom-inset:20px}
${asset('reader.css')}</style></head><body data-desktop="true"><article id="content">${paragraphs}</article>
<script>${asset('reader_anchors.js')}</script><script>${asset('reader.js')}</script><script>${asset('reader_translations.js')}</script><script>${assertions}</script></body></html>`;
const file = path.join(directory, 'test.html');
fs.writeFileSync(file, html);
const run = spawnSync(process.env.READER_TEST_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  ['--headless', '--disable-gpu', '--no-first-run', '--user-data-dir=' + path.join(directory, 'profile'),
    '--window-size=1200,900', '--virtual-time-budget=4000', '--dump-dom', require('node:url').pathToFileURL(file).href],
  {encoding:'utf8', windowsHide:true, timeout:30000, maxBuffer:4*1024*1024});
const result = run.stdout?.match(/data-result="([^"]*)"/)?.[1];
console.log(result || run.error?.message || '浏览器未返回结果');
if (result !== 'PASS') process.exitCode = 1;
