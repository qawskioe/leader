"""只监听本机的 TTS NDJSON 流；一条请求只生成一句公开台词。"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import threading

from cloud_provider import MODEL, synthesize, validate_request, load_config, prepare

ROOT = Path(__file__).resolve().parent
gate = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    # HTTP/1.0 以关闭连接标记响应结束；客户端仍须收到应用层 done。
    def log_message(self, *_args):
        pass

    def reply(self, status, value):
        data = json.dumps(value, ensure_ascii=True).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorize(self):
        expected = (ROOT / 'runtime/gateway-key.txt').read_text(encoding='utf-8').strip()
        if not secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + expected):
            self.reply(401, {'error': 'Unauthorized'})
            return False
        return True

    def do_GET(self):
        if not self.authorize():
            return
        if self.path != '/local/status':
            self.reply(404, {'error': 'Not found'})
            return
        try:
            config = load_config()
            state = {'configured':True,'project_id':config['project_id'],'stop_at_utc':config['stop_at_utc']}
        except (ValueError,OSError) as error:
            state = {'configured':False,'configuration_error':str(error)}
        self.reply(200, {'service': 'leader-gemini-tts', 'provider':'Google Cloud Text-to-Speech',
                         'model': MODEL, 'busy': gate.locked(), **state})

    def do_POST(self):
        self.connection.settimeout(45)
        if not self.authorize():
            return
        if self.path != '/speak':
            self.reply(404, {'error': 'Not found'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096 or self.headers.get('Transfer-Encoding'):
                raise ValueError('Invalid body size')
            body = validate_request(json.loads(self.rfile.read(size)))
        except (ValueError, TypeError, KeyError):
            self.reply(422, {'error': '需要 text(1-200字)、style、voice；不允许其他字段'})
            return
        if not gate.acquire(blocking=False):
            self.reply(429, {'error': '另一句正在合成，请等待完成'})
            return
        source = None
        try:
            self.send_response(200)
            self.send_header('Content-Type', 'application/x-ndjson')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Connection', 'close')
            self.end_headers()
            source = synthesize(body)
            for packet in source:
                self.wfile.write(json.dumps(packet, ensure_ascii=True).encode('utf-8') + b'\n')
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except Exception as error:
            # 只允许由本适配器生成的错误内容，避免任意异常回显机密。
            message = str(error) if isinstance(error, (ValueError, RuntimeError, TimeoutError)) else 'TTS 服务内部错误'
            try:
                self.wfile.write(json.dumps({'type': 'error', 'error': message}, ensure_ascii=True).encode() + b'\n')
                self.wfile.flush()
            except OSError:
                pass
        finally:
            if source is not None:
                source.close()
            gate.release()


if __name__ == '__main__':
    try:
        prepare()
    except Exception:
        # 保持本机接口可访问；具体配置／认证错误由请求路径返回。
        print('Cloud TTS startup preparation failed; configuration or login needs attention',flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18092), Handler).serve_forever()
