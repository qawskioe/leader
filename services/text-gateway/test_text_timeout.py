import json
import unittest
from unittest.mock import patch
from text_model import complete


class Response:
    def __init__(self, clock): self.clock=clock
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def __iter__(self):
        self.clock[0]=120
        yield b'data: '+json.dumps({'type':'response.completed','response':{'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'{}'}]}]}}).encode()


class TimeoutTests(unittest.TestCase):
    def call(self,limit=None):
        config={'url':'https://fixture.invalid','key':'fixture','model':'fixture'}
        if limit is not None: config['total_timeout_seconds']=limit
        clock=[0]
        with patch('text_model.urllib.request.build_opener') as opener, patch('text_model.time.monotonic',side_effect=lambda:clock[0]):
            opener.return_value.open.return_value=Response(clock)
            return complete('fixture',config)

    def test_short_default_still_times_out(self):
        result=self.call()
        self.assertFalse(result['ok'])
        self.assertEqual(result['timeout_kind'],'total')
        self.assertEqual(result['stream_diagnostic']['end'],'total_timeout')

    def test_builder_allows_completed_120_second_response(self):
        self.assertTrue(self.call(180)['ok'])

    def test_invalid_limit(self):
        self.assertFalse(self.call(100000)['ok'])
