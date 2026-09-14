"""验证实际 Flutter Web 产物；只使用演示状态，截图不包含凭据。"""
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import json
import re
from playwright.sync_api import sync_playwright, expect

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:8123/index.html?page=ai&device=desktop')
parser.add_argument('--chrome', default='C:/Program Files/Google/Chrome/Application/chrome.exe')
parser.add_argument('--output', default='build/flutter-newui-design/checks')
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
errors, remote = [], []


def tap(page, locator):
    locator.wait_for()
    box = locator.bounding_box()
    assert box and 0 <= box['y'] < page.viewport_size['height']
    # Flutter 的菜单屏障参与事件转发，使用真实鼠标坐标完成点击。
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    page.wait_for_timeout(220)


def reveal(page, locator):
    for _ in range(24):
        box = locator.bounding_box()
        assert box
        height = page.viewport_size['height']
        if 20 <= box['y'] and box['y'] + box['height'] < height - 20:
            return
        page.mouse.move(page.viewport_size['width'] - 35, height * .65)
        page.mouse.wheel(0, max(-600, min(600, box['y'] - height * .4)))
        page.wait_for_timeout(120)
    raise AssertionError('无法将目标控件滚动到视口')


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=args.chrome, headless=True)
    context = browser.new_context(viewport={'width': 1440, 'height': 1100}, reduced_motion='reduce')

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
    page.goto(args.url)
    page.get_by_role('button', name='切换深浅主题').wait_for(timeout=60000)
    help_text = '演示无需真实密钥。输入仅保留在当前页面。'
    help_button = page.get_by_role('button', name=help_text, exact=True)
    help_content = page.get_by_text(help_text, exact=True).and_(page.locator('span'))
    help_button.focus()
    page.keyboard.press('Enter')
    expect(help_content).to_be_visible()
    page.screenshot(path=str(out / 'help-popover.png'))
    page.keyboard.press('Escape')
    expect(help_content).to_have_count(0)
    expect(help_button).to_be_focused()

    fetch = page.get_by_role('button', name='获取模型', exact=True)
    reveal(page, fetch)
    tap(page, fetch)
    expect(page.get_by_text('已获取 4 个演示模型', exact=True).and_(page.locator('span'))).to_be_visible()
    expect(fetch).to_be_enabled()
    page.screenshot(path=str(out / 'models-fetched.png'))
    tap(page, page.get_by_role('button', name='OpenAI Compatible', exact=True))
    expect(page.get_by_role('button', name='Anthropic', exact=True)).to_be_visible()
    page.screenshot(path=str(out / 'selector.png'))
    tap(page, page.get_by_role('button', name='Anthropic', exact=True))
    expect(page.get_by_role('button', name='Anthropic', exact=True)).to_have_count(1)

    bold = page.get_by_role('radio', name='加粗', exact=True)
    reveal(page, bold)
    tap(page, bold)
    expect(bold).to_be_checked()
    expect(page.get_by_role('radio', name='主题色', exact=True)).not_to_be_checked()
    thanks = page.get_by_role('checkbox', name='致谢', exact=True)
    reveal(page, thanks)
    tap(page, thanks)
    expect(thanks).to_be_checked()
    expect(page.get_by_role('checkbox', name='参考文献', exact=True)).to_be_checked()

    slider = page.get_by_role('slider').first
    reveal(page, slider)
    expect(slider).to_be_enabled()
    slider.focus()
    page.wait_for_timeout(200)
    expect(slider).to_be_enabled()
    page.keyboard.press('ArrowRight')
    expect(page.get_by_text('0.05', exact=True)).to_be_visible()
    reset = page.get_by_role('button', name='重置温度', exact=True)
    expect(reset).to_be_enabled()
    tap(page, reset)
    expect(page.get_by_text('0.00', exact=True)).to_be_visible()
    expect(reset).to_be_disabled()
    page.screenshot(path=str(out / 'translation.png'))

    for width in [390, 700, 1440, 1720]:
        page.set_viewport_size({'width': width, 'height': 1100})
        page.reload()
        toggle = page.get_by_role('button', name='切换深浅主题')
        toggle.wait_for(timeout=60000)
        page.screenshot(path=str(out / f'{width}-light.png'))
        tap(page, toggle)
        page.screenshot(path=str(out / f'{width}-dark.png'))
        tap(page, page.get_by_role('button', name='切换中英文'))
        tap(page, page.get_by_role('button', name='Adjust text size'))
        tap(page, page.get_by_role('button', name='Adjust text size'))
        page.screenshot(path=str(out / f'{width}-english-200.png'))
        endpoint_text = 'Enter the base address for the API.'
        endpoint_help = page.get_by_role('button', name=endpoint_text, exact=True)
        reveal(page, endpoint_help)
        tap(page, endpoint_help)
        page.mouse.move(1, 1)
        help_content = page.get_by_text(endpoint_text, exact=True).and_(page.locator('span'))
        expect(help_content).to_be_visible()
        bounds = help_content.bounding_box()
        assert bounds and bounds['x'] >= 0 and bounds['x'] + bounds['width'] <= width
        page.screenshot(path=str(out / f'{width}-help-200.png'))
        page.keyboard.press('Escape')
        expect(help_content).to_have_count(0)
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        last = page.get_by_role('slider').last
        reveal(page, last)
        page.screenshot(path=str(out / f'{width}-image-200.png'))
    assert not errors, errors
    assert not remote, sorted(set(remote))
    report = {'passed': True, 'widths': [390, 700, 1440, 1720],
              'themes': ['light', 'dark'], 'textScales': [1, 1.3, 2],
              'interactions': ['help keyboard open and Escape', 'fetch models result',
                               'provider menu', 'single style', 'multiple exclusions',
                               'keyboard slider step', 'reset', 'language', 'theme'],
              'pageErrors': errors, 'externalRuntimeHosts': remote}
    (out / 'verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    browser.close()
