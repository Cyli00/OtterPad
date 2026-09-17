// 截图标签支持方向键、Home / End，与文档内容无关的脚本不会阻塞正文。
const tabs = [...document.querySelectorAll('[role="tab"]')];
function selectTab(tab, focus = false) {
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
    document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
  }
  if (focus) tab.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', (event) => {
    const next = { ArrowRight: (index + 1) % tabs.length, ArrowLeft: (index + tabs.length - 1) % tabs.length, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    selectTab(tabs[next], true);
  });
});

const menu = document.querySelector('.mobile-menu');
document.addEventListener('click', (event) => {
  if (!menu.contains(event.target) || event.target.closest('a')) menu.open = false;
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && menu.open) {
    menu.open = false;
    menu.querySelector('summary').focus();
  }
});

// 切换语言时保留所在章节。
const languageLink = document.querySelector('[data-language-link]');
const languageUrl = languageLink.href;
const updateLanguageLink = () => { languageLink.href = languageUrl + location.hash; };
updateLanguageLink();
addEventListener('hashchange', updateLanguageLink);

const sections = [...document.querySelectorAll('.doc-section')];
if (sections.length) {
  const directory = document.querySelector('.docs-directory');
  const mobile = matchMedia('(max-width: 600px)');
  const updateDirectory = () => { directory.open = !mobile.matches; };
  updateDirectory();
  mobile.addEventListener('change', updateDirectory);
  directory.addEventListener('click', (event) => {
    if (mobile.matches && event.target.closest('a')) directory.open = false;
  });
  const links = [...document.querySelectorAll('.docs-sidebar nav a, .docs-toc a')];
  let scheduled = false;
  const updateSection = () => {
    const active = sections.findLast((section) => section.getBoundingClientRect().top <= 140) || sections[0];
    for (const link of links) {
      if (link.hash === `#${active.id}`) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    }
    scheduled = false;
  };
  addEventListener('scroll', () => {
    if (!scheduled) { scheduled = true; requestAnimationFrame(updateSection); }
  }, { passive: true });
  updateSection();
}
