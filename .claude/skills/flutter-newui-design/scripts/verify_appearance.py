"""通过真实浏览器操作验证外观组合；只允许 localhost 请求。"""
from io import BytesIO
from pathlib import Path
from urllib.parse import urlsplit
import json

from PIL import Image
from playwright.sync_api import sync_playwright, expect

out = Path('build/flutter-newui-design/checks')
out.mkdir(parents=True, exist_ok=True)
base = 'http://127.0.0.1:8123/'
errors, remote = [], []


def reveal(page, target):
    for _ in range(55):
        box = target.bounding_box()
        assert box, '缺少目标控件'
        height = page.viewport_size['height']
        if 16 <= box['y'] and box['y'] + box['height'] < height - 16:
            return
        page.mouse.move(page.viewport_size['width'] - 8, height * .55)
        page.mouse.wheel(0, max(-700, min(700, box['y'] - height * .4)))
        page.wait_for_timeout(80)
    raise AssertionError('控件未进入视口')


def tap(page, target):
    reveal(page, target)
    box = target.bounding_box()
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    page.wait_for_timeout(280)


def pixel(page, x=3, y=3):
    return Image.open(BytesIO(page.screenshot())).convert('RGB').getpixel((int(x), int(y)))


def paper_pixel(page):
    target = page.get_by_text('正文 / 译文与插图', exact=True)
    reveal(page, target)
    box = target.bounding_box()
    return pixel(page, box['x'], box['y'] - 6)


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='C:/Program Files/Google/Chrome/Application/chrome.exe', headless=True)
    context = browser.new_context(viewport={'width': 1720, 'height': 1200}, color_scheme='light', reduced_motion='reduce')

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
    page.goto(base + 'demo-appearance.html')
    expect(page.locator('iframe')).to_have_count(3)
    for title in ['桌面预览', 'Xiaomi 15 预览', 'iPhone 17 Pro 预览']:
        page.frame_locator(f'iframe[title="{title}"]').get_by_role('button', name='切换深浅主题').wait_for(timeout=60000)
    page.wait_for_timeout(600)
    page.screenshot(path=str(out / 'appearance-paired.png'))
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')

    for device, width in [('desktop', 1100), ('xiaomi15', 400), ('iphone17pro', 402)]:
        page.set_viewport_size({'width': width, 'height': 960})
        page.emulate_media(color_scheme='light')
        page.goto(base + f'index.html?page=appearance&device={device}')
        theme = page.get_by_role('button', name='切换深浅主题')
        theme.wait_for(timeout=60000)
        expect(page.get_by_role('radio', name='自动', exact=True)).to_be_checked()
        light = pixel(page)
        page.emulate_media(color_scheme='dark')
        page.wait_for_timeout(300)
        assert pixel(page) != light, '跟随系统未响应明暗变化'
        page.screenshot(path=str(out / f'appearance-{device}-dark.png'))
        tap(page, page.get_by_role('radio', name='浅色', exact=True))
        assert pixel(page) == light
        page.emulate_media(color_scheme='light')
        page.screenshot(path=str(out / f'appearance-{device}-light.png'))

        tap(page, page.get_by_role('button', name='阅读纸面 跟随应用', exact=True))
        tap(page, page.get_by_role('menuitem', name='米纸', exact=True))
        pinned = paper_pixel(page)
        tap(page, page.get_by_role('radio', name='深色', exact=True))
        assert paper_pixel(page) == pinned, '固定纸面随应用明暗发生变化'
        page.screenshot(path=str(out / f'appearance-{device}-pinned-sepia.png'))

        tap(page, page.get_by_role('radio', name='PDF', exact=True))
        page.get_by_text('PDF / 原稿版面样例', exact=True).wait_for()
        page.screenshot(path=str(out / f'appearance-{device}-pdf.png'))
        tap(page, page.get_by_role('button', name='文献信息', exact=True))
        page.get_by_role('alertdialog').wait_for()
        page.screenshot(path=str(out / f'appearance-{device}-document-dialog.png'))
        page.keyboard.press('Escape')
        expect(page.get_by_role('alertdialog')).to_have_count(0)

        tap(page, page.get_by_role('button', name='编辑收藏夹', exact=True))
        name = page.get_by_role('textbox').last
        tap(page, name)
        page.keyboard.press('Control+A')
        page.keyboard.insert_text('夜读札记')
        page.screenshot(path=str(out / f'appearance-{device}-edit-dialog.png'))
        tap(page, page.get_by_role('button', name='保存', exact=True))
        expect(page.get_by_text('夜读札记', exact=True)).to_have_count(1)
        page.wait_for_timeout(4300)

        tap(page, page.get_by_role('button', name='显示提示', exact=True))
        expect(page.get_by_role('group', name='这是一条预览提示，阅读位置已保留', exact=True)).to_be_visible()
        page.screenshot(path=str(out / f'appearance-{device}-snackbar.png'))
        page.wait_for_timeout(4300)
        tap(page, page.get_by_role('button', name='错误示例', exact=True))
        expect(page.get_by_text('这是一条模拟错误，备注与外观选择仍保留。')).to_have_count(1)
        page.screenshot(path=str(out / f'appearance-{device}-alert.png'))
        tap(page, page.get_by_role('button', name='重试', exact=True))
        expect(page.get_by_text('这是一条模拟错误，备注与外观选择仍保留。')).to_have_count(0)
        page.wait_for_timeout(4300)

        tap(page, page.get_by_role('button', name='切换中英文', exact=True))
        tap(page, page.get_by_role('button', name='Adjust text size', exact=True))
        tap(page, page.get_by_role('button', name='Adjust text size', exact=True))
        page.screenshot(path=str(out / f'appearance-{device}-english-200.png'))
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    assert not errors, errors
    assert not remote, sorted(set(remote))
    report = {'passed': True, 'devices': ['desktop 1100', 'Xiaomi 15 400', 'iPhone 17 Pro 402'], 'checks': ['paired light and dark', 'system brightness', 'pinned paper pixel stability', 'PDF sample', 'document dialog and Escape', 'edit collection and save', 'snackbar', 'error recovery', 'dark English 200%'], 'pageErrors': errors, 'externalRuntimeHosts': remote}
    (out / 'appearance-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    browser.close()
