import json
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
if __name__=='__main__':unittest.main()
