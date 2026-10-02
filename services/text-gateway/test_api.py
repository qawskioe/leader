"""对已启动的本机网关验证协议拒绝，不调用上游模型。"""
import json
from pathlib import Path
import unittest
import urllib.request
import urllib.error

ROOT=Path(__file__).resolve().parent
class GatewayContract(unittest.TestCase):
    def request(self,path,body=None,authorized=True):
        headers={}
        if authorized:
            headers['Authorization']='Bearer '+(ROOT/'runtime/gateway-key.txt').read_text(encoding='utf-8').strip()
        if body is not None: headers['Content-Type']='application/json'
        req=urllib.request.Request('http://127.0.0.1:18090'+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(req,timeout=5) as response:return response.status
        except urllib.error.HTTPError as error:return error.code

    def test_text_only(self):
        self.assertEqual(self.request('/local/status'),200)
        self.assertEqual(self.request('/game/exchange',{'mode':'decision','prompt':'hello'},False),401)
        for mode in ['warm','transcribe','speak']:
            self.assertEqual(self.request('/game/exchange',{'mode':mode,'prompt':'hello'}),422)
        self.assertEqual(self.request('/game/exchange',{'mode':'decision','prompt':'hello','wav_base64':'AA=='}),422)
        self.assertEqual(self.request('/voice.html'),404)
        self.assertEqual(self.request('/game/stream'),404)

if __name__=='__main__':unittest.main()
