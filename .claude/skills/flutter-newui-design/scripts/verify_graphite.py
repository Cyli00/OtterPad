"""验收石墨、系统字体、三视口及基础组件；所有运行时请求限定 localhost。"""
from hashlib import sha256
from pathlib import Path
from urllib.parse import urlsplit
import json

from PIL import Image
from playwright.sync_api import sync_playwright, expect

base = 'http://127.0.0.1:8123/'
out = Path('build/flutter-newui-design/checks')
out.mkdir(parents=True, exist_ok=True)
devices = [('desktop', 1100, 960, 1), ('xiaomi15', 400, 890, 3), ('iphone17pro', 402, 874, 3)]
errors, remote = [], []


def reveal(page, target):
    for _ in range(65):
        box = target.bounding_box()
        assert box, '缺少目标控件'
        height = page.viewport_size['height']
        if 12 <= box['y'] and box['y'] + box['height'] < height - 12:
            return
        page.mouse.move(page.viewport_size['width'] - 6, height * .55)
        page.mouse.wheel(0, max(-700, min(700, box['y'] - height * .4)))
        page.wait_for_timeout(80)
    raise AssertionError('控件未进入视口')


def tap(page, target):
    reveal(page, target)
    page.wait_for_timeout(180)
    box = target.bounding_box()
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    page.wait_for_timeout(350)


def font(page, name):
    # 字体重排会改变外层滚动范围，先停止滚动并回到固定工具区再比较。
    page.mouse.move(page.viewport_size['width'] - 6, page.viewport_size['height'] * .5)
    page.mouse.wheel(0, -20000)
    page.wait_for_timeout(600)
    tap(page, page.get_by_role('button', name='显示设置', exact=True))
    page.get_by_role('alertdialog').wait_for()
    tap(page, page.get_by_role('radio', name=name, exact=True))
    tap(page, page.get_by_role('button', name='保存', exact=True))
    expect(page.get_by_role('alertdialog')).to_have_count(0)


def toolbar(page, name):
    # 主题与字体切换后布局仍可能重排，工具栏用键盘焦点验证激活行为。
    target = page.get_by_role('button', name=name, exact=True)
    reveal(page, target)
    target.focus()
    page.keyboard.press('Enter')
    page.wait_for_timeout(600)


def shot(page, name):
    page.mouse.move(1, 1)
    page.wait_for_timeout(200)
    page.screenshot(path=str(out / f'graphite-{name}.png'))


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='C:/Program Files/Google/Chrome/Application/chrome.exe', headless=True)

    def route(request):
        host = urlsplit(request.request.url).hostname
        if host and host not in ['localhost', '127.0.0.1']:
            remote.append(host)
            request.abort()
        else:
            request.continue_()

    shell = browser.new_context(viewport={'width': 1920, 'height': 1200}, color_scheme='light', reduced_motion='reduce')
    shell.route('**/*', route)
    page = shell.new_page()
    page.on('pageerror', lambda error: errors.append(str(error)))
    for name in ['demo.html', 'demo-backup_setting.html', 'demo-default_widget.html', 'demo-appearance.html']:
        page.goto(base + name)
        expect(page.locator('iframe')).to_have_count(3)
        for title in ['桌面预览', 'Xiaomi 15 预览', 'iPhone 17 Pro 预览']:
            page.frame_locator(f'iframe[title="{title}"]').get_by_role('button', name='显示设置').wait_for(timeout=60000)
        shot(page, name.removesuffix('.html') + '-paired')
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    manifest = shell.request.get(base + 'assets/FontManifest.json').json()
    assert {'sans-serif', 'serif', 'Segoe UI Emoji'}.issubset({entry['family'] for entry in manifest})
    for asset, file in [('system-sans-latin', 'segoeui.ttf'), ('system-sans', 'msyh.ttc'), ('system-serif-latin', 'times.ttf'), ('system-serif', 'simsun.ttc'), ('system-emoji', 'seguiemj.ttf')]:
        response = shell.request.get(base + 'assets/' + asset)
        assert response.ok
        assert sha256(response.body()).digest() == sha256((Path('C:/Windows/Fonts') / file).read_bytes()).digest()
    shell.close()

    for device, width, height, dpr in devices:
        context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=dpr, color_scheme='light', reduced_motion='reduce')
        context.route('**/*', route)
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        for name in ['widgets', 'appearance', 'ai', 'backup']:
            page.goto(base + f'index.html?page={name}&device={device}')
            page.get_by_role('button', name='显示设置').wait_for(timeout=60000)
            shot(page, f'{name}-{device}-sans')
            with Image.open(out / f'graphite-{name}-{device}-sans.png') as capture:
                assert capture.size == (width * dpr, height * dpr)
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            if name == 'widgets':
                info = page.get_by_role('radio', name='信息', exact=True)
                tap(page, info)
                expect(info).to_be_checked()
                expect(page.get_by_role('radio', name='错误', exact=True)).not_to_be_checked()
                tap(page, info)
                expect(info).to_be_checked()
                info.focus()
                page.keyboard.press('Tab')
                page.keyboard.press('Space')
                expect(page.get_by_role('radio', name='警告', exact=True)).to_be_checked()
                tap(page, page.get_by_role('button', name='文献信息', exact=True))
                page.get_by_role('alertdialog').wait_for()
                shot(page, f'dialog-{device}')
                page.keyboard.press('Escape')
                tap(page, page.get_by_role('button', name='编辑收藏夹', exact=True))
                page.get_by_role('alertdialog').wait_for()
                shot(page, f'favorite-editor-{device}')
                tap(page, page.get_by_role('button', name='取消', exact=True))
                covers = page.get_by_role('radio', name='4', exact=True)
                tap(page, covers)
                expect(covers).to_be_checked()
                shot(page, f'favorite-cards-{device}')
                tap(page, page.get_by_role('button', name='结果提示', exact=True))
                expect(page.get_by_role('group', name='演示设置已更新', exact=True)).to_be_visible()
                shot(page, f'snackbar-{device}')
                page.wait_for_timeout(4100)
            elif name == 'appearance':
                expect(page.get_by_text('强调色', exact=True)).to_have_count(0)
                expect(page.get_by_text('阅读纸面', exact=True)).to_have_count(1)
                tap(page, page.get_by_role('button', name='阅读纸面 跟随应用', exact=True))
                tap(page, page.get_by_role('menuitem', name='米纸', exact=True))
                tap(page, page.get_by_role('radio', name='深色', exact=True))
                expect(page.get_by_role('button', name='阅读纸面 米纸', exact=True)).to_have_count(1)
                shot(page, f'fixed-paper-{device}')
                tap(page, page.get_by_role('radio', name='PDF', exact=True))
                shot(page, f'pdf-{device}')
            elif name == 'ai':
                tap(page, page.get_by_role('button', name='获取模型', exact=True))
                page.locator('flt-semantics-host').get_by_text('已获取 4 个演示模型', exact=True).wait_for(timeout=10000)
            font(page, '衬线')
            shot(page, f'{name}-{device}-serif')
            font(page, '无衬线')
            if name == 'appearance':
                tap(page, page.get_by_role('radio', name='深色', exact=True))
            else:
                toolbar(page, '切换深浅主题')
            shot(page, f'{name}-{device}-dark')
            toolbar(page, '切换中英文')
            toolbar(page, 'Adjust text size')
            toolbar(page, 'Adjust text size')
            shot(page, f'{name}-{device}-english-200')
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            print(f'Verified {name} / {device}', flush=True)
        context.close()
    assert not errors, errors
    assert not remote, sorted(set(remote))
    report = {'passed': True, 'pages': ['ai', 'backup', 'widgets', 'appearance'], 'devices': [{'device': d, 'logicalSize': [w, h], 'dpr': r, 'pixelSize': [w*r, h*r]} for d, w, h, r in devices], 'fonts': ['system sans', 'system serif'], 'checks': ['font source bytes', 'three device shells', 'physical screenshot sizes', 'segmented exclusivity and keyboard', 'single field label', 'no accent picker', 'dialogs and Escape', 'favorite editor and covers', 'snackbar', 'fixed paper', 'model fetch', 'font switching', 'dark English 200%'], 'pageErrors': errors, 'externalRuntimeHosts': remote}
    (out / 'graphite-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    browser.close()
