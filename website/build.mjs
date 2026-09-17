import { readFile, writeFile, mkdir } from 'node:fs/promises';

// 静态页面与 Flutter 共用 ARB 文案；部署 website 目录即可，无运行时依赖。
const base = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, base), 'utf8');
const escape = (value) => String(value).replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[char]);
const header = await read('src/header.html');
const footer = await read('src/footer.html');

for (const locale of ['zh', 'en']) {
  const messages = JSON.parse(await read(`../lib/l10n/app_${locale}.arb`));
  for (const page of ['index', 'docs']) {
    const isDocs = page === 'docs';
    const directory = `${locale === 'en' ? 'en/' : ''}${isDocs ? 'docs/' : ''}`;
    const root = '../'.repeat(directory.split('/').filter(Boolean).length) || './';
    const home = `${root}${locale === 'en' ? 'en/' : ''}index.html`;
    const values = {
      ...messages, root, home,
      docs: home.replace('index.html', 'docs/index.html'),
      lang: locale === 'zh' ? 'zh-CN' : 'en',
      languageLabel: locale === 'zh' ? 'English' : '简体中文',
      languageUrl: `${root}${locale === 'zh' ? 'en/' : ''}${isDocs ? 'docs/' : ''}index.html`,
      pageTitle: isDocs ? messages.websiteDocsTitle : messages.websiteTitle,
      pageClass: isDocs ? 'docs-page' : 'home-page',
      libraryImage: locale === 'zh' ? 'desktop-library' : 'desktop-library-en',
    };
    const template = (await read(`src/${page}.html`))
      .replace('{{header}}', header).replace('{{footer}}', footer);
    const html = template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
      if (!(key in values)) throw new Error(`缺少文案：${locale}/${key}`);
      return escape(values[key]);
    });
    await mkdir(new URL(directory || './', base), { recursive: true });
    await writeFile(new URL(`${directory}index.html`, base), `${html.trimEnd()}\n`);
    console.log(`已生成 ${directory}index.html`);
  }
}
