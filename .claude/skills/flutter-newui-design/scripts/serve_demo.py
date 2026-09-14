"""本地预览：将已安装的系统衬线字体提供给 CanvasKit，不复制或打包字体。"""
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
            # Roboto 只是引擎默认家族的别名；实际字节仍来自本机宋体。
            for family, asset in {
                'serif': 'system-serif-latin',
                'Times New Roman': 'system-serif-latin',
                'SimSun': 'system-serif',
                'Roboto': 'system-serif',
            }.items():
                manifest.append({'family': family, 'fonts': [{'asset': asset}]})
            data = json.dumps(manifest).encode()
            mime = 'application/json'
        elif path == '/assets/system-serif':
            data = self.server.serif_path.read_bytes()
            mime = 'font/collection'
        elif path == '/assets/system-serif-latin':
            data = self.server.latin_path.read_bytes()
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
    if not serif.is_file() or not latin.is_file():
        parser.error('本预览桥接器需 Windows 自带宋体与 Times New Roman；不会自动下载替代字体。')
    if not (args.site / 'assets/FontManifest.json').is_file():
        parser.error('请先运行 build_demo.sh。')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(PreviewHandler, directory=str(args.site.resolve())))
    server.serif_path = serif
    server.latin_path = latin
    print(f'系统衬线预览：http://127.0.0.1:{args.port}/demo-default_widget.html', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
