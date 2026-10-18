import json
import io
import unittest
from unittest.mock import patch
from text_model import complete

class InstructionTests(unittest.TestCase):
    def test_outgoing_instructions_allow_skill_submission(self):
        captured=[]
        class Stream:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def __iter__(self):
                yield b'data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{}"}]}]}}\n'
        class Opener:
            def open(self,request,timeout):
                captured.append(json.loads(request.data));return Stream()
        with patch('text_model.urllib.request.build_opener',return_value=Opener()):
            result=complete('开始动手',{'model':'fixture','url':'https://example.invalid','key':'fixture'})
        self.assertTrue(result['ok'])
        self.assertNotIn('不执行',captured[0]['instructions'])
        self.assertIn('技能调用',captured[0]['instructions'])
    def test_gemini_output_budget_is_configurable_and_truncation_is_rejected(self):
        cfg={'model':'gemini-fixture','url':'https://example.invalid','key':'fixture','protocol':'gemini','max_output_tokens':8192}
        wire=b'data: {"candidates":[{"content":{"parts":[{"text":"{\\\"ok\\\":true}"}]},"finishReason":"STOP"}]}\n'
        with patch('text_model.urllib.request.build_opener') as factory:
            factory.return_value.open.return_value=io.BytesIO(wire)
            result=complete('同一现场',cfg)
            sent=json.loads(factory.return_value.open.call_args.args[0].data)
        self.assertTrue(result['ok'])
        self.assertEqual(sent['generationConfig']['maxOutputTokens'],8192)
        with patch('text_model.urllib.request.build_opener') as factory:
            factory.return_value.open.return_value=io.BytesIO(wire.replace(b'STOP',b'MAX_TOKENS'))
            result=complete('同一现场',cfg)
        self.assertFalse(result['ok'])
        self.assertNotIn('text',result,'被截断的片段不能当作完整角色决策')
    def test_invalid_gemini_output_budget_does_not_send(self):
        for budget in [True,0,'8192',32769]:
            with patch('text_model.urllib.request.build_opener') as factory:
                result=complete('现场',{'model':'fixture','protocol':'gemini','max_output_tokens':budget})
            self.assertFalse(result['ok'])
            factory.assert_not_called()
if __name__=='__main__':unittest.main()
