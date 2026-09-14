"""验收双端外壳与两个新增 Flutter 页面，不访问真实文件或服务。"""
from pathlib import Path
from urllib.parse import urlsplit
import json
from playwright.sync_api import sync_playwright, expect

out = Path('build/flutter-newui-design/checks')
out.mkdir(parents=True, exist_ok=True)
base = 'http://127.0.0.1:8123/'
errors, remote = [], []


def tap(page, target):
    box = target.bounding_box()
    assert box
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    page.wait_for_timeout(250)


def reveal(page, target):
    for _ in range(40):
        box = target.bounding_box()
        assert box
        height = page.viewport_size['height']
        if 20 <= box['y'] and box['y'] + box['height'] < height - 20:
            return
        page.mouse.move(page.viewport_size['width'] - 30, height * .6)
        page.mouse.wheel(0, max(-650, min(650, box['y'] - height * .4)))
        page.wait_for_timeout(100)
    raise AssertionError('控件无法滚动到视口')


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='C:/Program Files/Google/Chrome/Application/chrome.exe', headless=True)
    context = browser.new_context(viewport={'width': 1640, 'height': 1200}, reduced_motion='reduce')

    def route(request):
        host = urlsplit(request.request.url).hostname
        if host and host not in ['localhost', '127.0.0.1']:
            remote.append(host)
            request.abort()
        else:
            request.continue_()

    context.route('**/*', route)
    page = context.new_page()
    page.on('pageerror', lambda error: errors.append(str(error)))
    for file in ['demo.html', 'demo-backup_setting.html', 'demo-default_widget.html']:
        page.goto(base + file)
        expect(page.locator('iframe')).to_have_count(2)
        for title in ['桌面预览', '移动端预览']:
            page.frame_locator(f'iframe[title="{title}"]').get_by_role('button', name='切换深浅主题').wait_for(timeout=60000)
        page.screenshot(path=str(out / file.replace('.html', '-paired.png')))
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')

    for name in ['backup', 'widgets']:
        for device, width in [('desktop', 1100), ('mobile', 390)]:
            page.set_viewport_size({'width': width, 'height': 960})
            page.goto(base + f'index.html?page={name}&device={device}')
            theme = page.get_by_role('button', name='切换深浅主题')
            theme.wait_for(timeout=60000)
            page.screenshot(path=str(out / f'{name}-{device}.png'))
            if name == 'backup':
                local = page.get_by_role('button', name='本机 Zotero', exact=True)
                expect(local).to_have_count(1 if device == 'desktop' else 0)
                tap(page, page.get_by_role('button', name='配置', exact=True))
                sample = page.get_by_role('button', name='填入演示配置', exact=True)
                sample.wait_for()
                page.screenshot(path=str(out / f'backup-config-{device}.png'))
                tap(page, sample)
                tap(page, page.get_by_role('button', name='保存', exact=True))
                expect(page.get_by_role('button', name='编辑', exact=True)).to_be_visible()
                daily = page.get_by_role('radio', name='每日', exact=True)
                reveal(page, daily)
                tap(page, daily)
                expect(daily).to_be_checked()
                page.screenshot(path=str(out / f'backup-configured-{device}.png'))
            else:
                webdav = page.get_by_role('radio', name='WebDAV', exact=True)
                tap(page, webdav)
                expect(webdav).to_be_checked()
                expect(page.get_by_role('radio', name='S3', exact=True)).not_to_be_checked()
                info = page.get_by_role('radio', name='信息', exact=True)
                reveal(page, info)
                tap(page, info)
                expect(info).to_be_checked()
                expect(page.get_by_role('radio', name='错误', exact=True)).not_to_be_checked()
                tap(page, info)
                expect(info).to_be_checked()
                info.focus()
                page.keyboard.press('Tab')
                page.keyboard.press('Space')
                expect(page.get_by_role('radio', name='警告', exact=True)).to_be_checked()
                page.screenshot(path=str(out / f'selection-{device}.png'))
                document = page.get_by_role('button', name='文献信息', exact=True)
                reveal(page, document)
                tap(page, document)
                page.get_by_role('button', name='复制DOI', exact=True).wait_for()
                page.screenshot(path=str(out / f'document-dialog-{device}.png'))
                page.keyboard.press('Escape')
                edit = page.get_by_role('button', name='编辑收藏夹', exact=True)
                reveal(page, edit)
                tap(page, edit)
                page.get_by_role('button', name='保存', exact=True).wait_for()
                page.screenshot(path=str(out / f'favorite-dialog-{device}.png'))
                tap(page, page.get_by_role('button', name='取消', exact=True))
                covers = page.get_by_role('radio', name='4', exact=True)
                reveal(page, covers)
                tap(page, covers)
                expect(covers).to_be_checked()
                page.screenshot(path=str(out / f'favorite-cards-{device}.png'))
                result = page.get_by_role('button', name='结果提示', exact=True)
                reveal(page, result)
                tap(page, result)
                expect(page.get_by_role('group', name='演示设置已更新', exact=True)).to_be_visible()
                page.screenshot(path=str(out / f'snackbar-{device}.png'))
            reveal(page, theme)
            tap(page, theme)
            tap(page, page.get_by_role('button', name='切换中英文'))
            tap(page, page.get_by_role('button', name='Adjust text size'))
            tap(page, page.get_by_role('button', name='Adjust text size'))
            page.screenshot(path=str(out / f'{name}-{device}-dark-200.png'))
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    manifest = context.request.get(base + 'assets/FontManifest.json').json()
    families = {entry['family'] for entry in manifest}
    assert 'serif' in families and not families.intersection({'PaperSerif', 'PaperSans'})
    import hashlib
    system_font = context.request.get(base + 'assets/system-serif')
    assert system_font.ok
    assert hashlib.sha256(system_font.body()).digest() == hashlib.sha256(Path('C:/Windows/Fonts/simsun.ttc').read_bytes()).digest()
    latin_font = context.request.get(base + 'assets/system-serif-latin')
    assert latin_font.ok
    assert hashlib.sha256(latin_font.body()).digest() == hashlib.sha256(Path('C:/Windows/Fonts/times.ttf').read_bytes()).digest()
    assert not errors, errors
    assert not remote, sorted(set(remote))
    report = {'passed': True, 'pairedPages': 3, 'devices': ['desktop 1100', 'mobile 390'], 'pages': ['backup', 'widgets'], 'checks': ['system serif bytes', 'segmented exclusivity and keyboard', 'platform entry', 'configuration dialog and save', 'automatic backup', 'document dialog', 'favorite editor cancel', 'dynamic covers', 'snackbar', 'dark English 200%'], 'pageErrors': errors, 'externalRuntimeHosts': remote}
    (out / 'surfaces-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    browser.close()
