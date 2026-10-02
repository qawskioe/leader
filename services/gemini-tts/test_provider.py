"""零云端调用：完成边界、PCM、隐私字段、断流及 Godot HTTP 客户端。"""
import base64
import io
import json
from pathlib import Path
import subprocess
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from probe import events
from provider import packets, validate_request
import provider
import run as gateway


def audio(data=b'\0\0' * 960):
    return {'event_type': 'step.delta', 'delta': {'type': 'audio', 'mime_type': 'audio/l16',
                                                'data': base64.b64encode(data).decode()}}


DONE = {'event_type': 'interaction.completed', 'interaction': {'status': 'completed'}}


class ProviderTests(unittest.TestCase):
    def test_structured_style_never_enters_transcript(self):
        request = provider.build_request({'text':'好，我听你的。','style':'压住委屈','voice':'Kore'})
        part = request['input'][0]['content'][0]
        self.assertEqual(part['text'], '好，我听你的。')
        self.assertEqual(part['annotations'], [{'type':'speech_metadata','style':'压住委屈'}])
        self.assertEqual(request['model'], 'gemini-3.8-flash-tts')
        self.assertEqual(request['response_format']['mime_type'], 'audio/l16')
        self.assertTrue(request['stream'])

    def test_each_character_voice_is_forwarded(self):
        for voice in ['Puck', 'Aoede', 'Kore', 'Charon']:
            with self.subTest(voice=voice):
                body = provider.build_request({'text':'好','style':'平静','voice':voice})
                self.assertEqual(body['generation_config']['speech_config'], [{'voice':voice}])

    def test_quota_sse_and_json(self):
        value = {'error':{'message':'Quota exceeded: generate_content_free_tier_requests, limit: 10, model: tts\nPlease retry in 29.13s.'}}
        encoded = json.dumps(value).encode()
        expected = {'retry_after_seconds':30,'limit':10,'free_request_quota':True}
        self.assertEqual(provider.quota_details(encoded),expected)
        self.assertEqual(provider.quota_details(b'event: error\ndata: '+encoded+b'\n\n'),expected)
        self.assertEqual(provider.quota_details(encoded,'42')['retry_after_seconds'],42)

    def test_cooldown_makes_no_network_request(self):
        with patch.object(provider,'_retry_at',time.monotonic()+20), patch.object(provider.urllib.request,'build_opener') as network:
            with self.assertRaises(provider.QuotaError):
                list(provider.synthesize({'text':'好','style':'neutral','voice':'Kore'}))
            network.assert_not_called()

    def test_sse_done_and_split_data(self):
        source = io.BytesIO(b'event: interaction.completed\r\ndata: {"interaction":\r\ndata: {"status":"completed"}}\r\n\r\ndata: [DONE]\n\n')
        self.assertEqual(list(events(source)), [DONE])

    def test_audio_and_explicit_completion(self):
        result = list(packets([audio(b'\0\0' * 6000), DONE]))
        self.assertEqual([p['sequence'] for p in result[:-1]], [0, 1, 2])
        self.assertEqual(result[-1], {'type': 'done', 'chunks': 3, 'audio_bytes': 12000})

    def test_missing_or_bad_completion(self):
        for source in [[audio()], [DONE], [audio(), {'event_type': 'interaction.completed', 'interaction': {'status': 'failed'}}], [audio(), {'event_type': 'error'}]]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                list(packets(source))

    def test_invalid_pcm_and_limit(self):
        for data in [b'', b'\0', b'\0\0' * 720001]:
            with self.assertRaises(ValueError):
                list(packets([audio(data), DONE]))

    def test_private_fields_and_invalid_styles_rejected(self):
        valid = {'text': '好，我听你的。', 'style': 'restrained', 'voice': 'Kore'}
        self.assertEqual(validate_request(valid), valid)
        for change in [{'private_interpretation': '秘密'}, {'text': ' '}, {'text': '字' * 201}, {'style': ' '}, {'style': '字'*301}, {'style': 3}, {'voice': 'unknown'}]:
            with self.assertRaises(ValueError):
                validate_request(valid | change)

    def test_http_rejects_private_input_without_upstream(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), gateway.Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        key = (gateway.ROOT / 'runtime/gateway-key.txt').read_text(encoding='utf-8').strip()
        try:
            with patch.object(gateway, 'synthesize') as upstream:
                for body, token, status in [
                    ({'text':'好','style':'neutral','voice':'Kore','private_interpretation':'PRIVATE'},key,422),
                    ({'text':'好','style':'neutral','voice':'Kore'},'invalid',401),
                    ({'text':'','style':'neutral','voice':'Kore'},key,422),
                ]:
                    request = urllib.request.Request(f'http://127.0.0.1:{server.server_port}/speak',
                              data=json.dumps(body).encode(), headers={'Authorization':'Bearer '+token})
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        urllib.request.urlopen(request,timeout=3)
                    self.assertEqual(caught.exception.code,status)
                upstream.assert_not_called()
        finally:
            server.shutdown()
            server.server_close()


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if set(body) != {'text', 'style', 'voice'}:
            raise AssertionError('Godot 向 TTS 发送了多余字段')
        mode = body['text']
        self.send_response(429 if mode == 'http_error' else 200)
        self.send_header('Connection', 'close')
        self.end_headers()
        if mode == 'http_error':
            self.wfile.write(b'{"error":"quota"}')
            return
        try:
            if mode == 'bad_json':
                self.wfile.write(b'not json\n')
                return
            for i in range(8):
                packet = {'type': 'audio', 'sequence': 99 if mode == 'wrong_order' else i,
                          'sample_rate': 24000, 'pcm_base64': audio()['delta']['data']}
                data = json.dumps(packet).encode() + b'\n'
                # 分开写一条 JSON，检验 TCP 分包不能当成消息边界。
                self.wfile.write(data[:50]); self.wfile.flush()
                self.wfile.write(data[50:]); self.wfile.flush()
                time.sleep(0.04)
            if mode == 'truncated':
                return
            if mode == 'error':
                packet = {'type': 'error', 'error': 'fixture upstream failure'}
            else:
                packet = {'type': 'done', 'chunks': 8, 'audio_bytes': 1 if mode == 'wrong_done' else 15360}
            self.wfile.write(json.dumps(packet).encode() + b'\n')
        except OSError:
            pass


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProviderTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    server = ThreadingHTTPServer(('127.0.0.1', 18093), FixtureHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run(['D:/soft/dev/Godot/Godot_v4.6.2-stable_win64_console.exe', '--headless',
                        '--path', str(Path(__file__).resolve().parents[2]), '--script', 'tools/test_tts.gd'], check=True, timeout=25)
    finally:
        server.shutdown()
        server.server_close()
