"""验证中断的生成永远不能当作完整决策交付，诊断不包含台词。"""
import io
import json
import unittest
from unittest.mock import Mock, patch
import text_model

class ResponseStreamTests(unittest.TestCase):
    config={'url':'http://localhost/responses','key':'test-secret','model':'test'}

    def run_stream(self, events, done=False):
        wire=b''.join(b'data: '+json.dumps(e).encode()+b'\n\n' for e in events)
        if done:
            wire+=b'data: [DONE]\n\n'
        opener=Mock()
        opener.open.return_value=io.BytesIO(wire)
        with patch.object(text_model.urllib.request,'build_opener',return_value=opener):
            return text_model.complete('private-prompt',self.config)

    def test_eof_partial_json_is_not_a_decision(self):
        result=self.run_stream([{'type':'response.created'},
            {'type':'response.output_text.delta','delta':'{"speech":"private"}'}])
        self.assertFalse(result['ok'])
        self.assertTrue(result['retryable'])
        self.assertNotIn('text',result)
        self.assertEqual(result['stream_diagnostic'],{'event_count':2,
            'last_event_type':'response.output_text.delta','text_chars':20,'end':'eof'})
        self.assertNotIn('private',json.dumps(result))
        self.assertNotIn('test-secret',json.dumps(result))

    def test_done_without_completed_is_not_success(self):
        result=self.run_stream([{'type':'response.output_text.done','text':'{}'}],True)
        self.assertFalse(result['ok'])
        self.assertEqual(result['stream_diagnostic']['end'],'done_marker')

    def test_failure_event_is_distinct_from_eof(self):
        result=self.run_stream([{'type':'response.failed','response':{'error':{'message':'private'}}}])
        self.assertFalse(result['ok'])
        self.assertEqual(result['stream_diagnostic']['end'],'failure_event')
        self.assertNotIn('private',json.dumps(result))

    def test_complete_is_delivered(self):
        result=self.run_stream([{'type':'response.completed','response':{
            'status':'completed','model':'test','output':[{'type':'message',
                'content':[{'type':'output_text','text':'{}'}]}]}}])
        self.assertTrue(result['ok'])
        self.assertEqual(result['text'],'{}')

if __name__=='__main__':unittest.main()
