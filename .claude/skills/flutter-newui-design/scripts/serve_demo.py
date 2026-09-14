"""本地预览：将已安装的系统 sans／serif 提供给 CanvasKit，不复制或打包字体。"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import io
import json
import os


class PreviewHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        path = urlsplit(self.path).path
        if path == '/assets/FontManifest.json':
            manifest = json.loads((Path(self.directory) / 'assets/FontManifest.json').read_text())
            # Roboto 为引擎兜底别名，使用本机微软雅黑，避免网络字体请求。
            for family, asset in {
                'serif': 'system-serif-latin',
                'Times New Roman': 'system-serif-latin',
                'SimSun': 'system-serif',
                'sans-serif': 'system-sans-latin',
                'Segoe UI': 'system-sans-latin',
                'Microsoft YaHei': 'system-sans',
                'Roboto': 'system-sans',
                # 收藏夹身份用 emoji：交给本机表情字体，避免 CanvasKit 去 fonts.gstatic.com 取字体。
                'Segoe UI Emoji': 'system-emoji',
                'Noto Color Emoji': 'system-emoji',
            }.items():
                fonts = [{'asset': asset}]
                if asset.startswith('system-sans'):
                    fonts.append({'asset': asset + '-bold', 'weight': 700})
                manifest.append({'family': family, 'fonts': fonts})
            data = json.dumps(manifest).encode()
            mime = 'application/json'
        elif path == '/assets/system-serif':
            data = self.server.serif_path.read_bytes()
            mime = 'font/collection'
        elif path == '/assets/system-serif-latin':
            data = self.server.latin_path.read_bytes()
            mime = 'font/ttf'
        elif path.removeprefix('/assets/') in self.server.sans_paths:
            data = self.server.sans_paths[path.removeprefix('/assets/')].read_bytes()
            mime = 'font/ttf'
        else:
            return super().send_head()
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        return io.BytesIO(data)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_message(self, format, *args):
        # 后台预览不依赖终端日志管道，避免关闭终端后请求写日志失败。
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site', type=Path)
    parser.add_argument('--port', type=int, default=8123)
    args = parser.parse_args()
    serif = Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts/simsun.ttc'
    latin = serif.parent / 'times.ttf'
    sans = {name: serif.parent / file for name, file in {
        'system-sans-latin': 'segoeui.ttf', 'system-sans-latin-bold': 'segoeuib.ttf',
        'system-sans': 'msyh.ttc', 'system-sans-bold': 'msyhbd.ttc',
        'system-emoji': 'seguiemj.ttf',
    }.items()}
    if not all(path.is_file() for path in [serif, latin, *sans.values()]):
        parser.error('需要本机 Segoe UI、微软雅黑、Times New Roman、宋体和 Segoe UI Emoji；不会下载替代字体。')
    if not (args.site / 'assets/FontManifest.json').is_file():
        parser.error('请先运行 build_demo.sh。')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(PreviewHandler, directory=str(args.site.resolve())))
    server.serif_path = serif
    server.latin_path = latin
    server.sans_paths = sans
    print(f'系统字体预览：http://127.0.0.1:{args.port}/demo-default_widget.html', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
