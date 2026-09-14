"""生成双端展示外壳；业务界面始终来自同一份 Flutter 编译产物。"""
from pathlib import Path
import sys

site = Path(sys.argv[1])
template = (Path(__file__).resolve().parent.parent / 'examples/ai_settings/preview.html').read_text(encoding='utf-8')
for name, page, title in [
    ('demo.html', 'ai', 'AI 设置'),
    ('demo-backup_setting.html', 'backup', '数据管理'),
    ('demo-default_widget.html', 'widgets', '基础组件'),
]:
    (site / name).write_text(template.replace('{{PAGE}}', page).replace('{{TITLE}}', title), encoding='utf-8')
    print(site / name)
