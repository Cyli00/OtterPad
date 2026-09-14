"""生成双端展示外壳；业务界面始终来自同一份 Flutter 编译产物。"""
from pathlib import Path
import sys

site = Path(sys.argv[1])
template = (Path(__file__).resolve().parent.parent / 'examples/ai_settings/preview.html').read_text(encoding='utf-8')
for name, page, title in [
    ('demo.html', 'ai', 'AI 设置'),
    ('demo-backup_setting.html', 'backup', '数据管理'),
    ('demo-default_widget.html', 'widgets', '基础组件'),
    ('demo-appearance.html', 'appearance', '外观验证'),
]:
    html = template.replace('{{PAGE}}', page).replace('{{TITLE}}', title)
    if page == 'appearance':
        html = html.replace('device=desktop', 'device=desktop&theme=light').replace('device=xiaomi15', 'device=xiaomi15&theme=dark').replace('device=iphone17pro', 'device=iphone17pro&theme=light')
        html = html.replace('各窗口可独立操作', '初始桌面／iPhone 浅色，Xiaomi 深色；各窗口可独立操作')
    (site / name).write_text(html, encoding='utf-8')
    print(site / name)
    if page == 'widgets':
        (site / 'default_widget.html').write_text(html, encoding='utf-8')
