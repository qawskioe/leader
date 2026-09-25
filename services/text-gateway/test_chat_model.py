import json
import time
import unittest
from chat_model import read_stream


class StreamTests(unittest.TestCase):
    def stream(self, finish='stop', done=True):
        events = [{'choices': [{'delta': {'content': '{"intent":"none"}'}, 'finish_reason': None}]},
                  {'choices': [{'delta': {}, 'finish_reason': finish}]},
                  {'choices': [], 'usage': {'prompt_tokens': 100, 'completion_tokens': 8}}]
        lines = [b'data: ' + json.dumps(e).encode() for e in events]
        return lines + ([b'data: [DONE]'] if done else [])

    def test_complete_and_usage(self):
        result = read_stream(self.stream(), time.monotonic(), 'deepseek-flash')
        self.assertTrue(result['ok'])
        self.assertEqual(result['usage']['prompt_tokens'], 100)

    def test_truncated_or_missing_end_rejected(self):
        for finish, done in [('length', True), ('stop', False), ('tool_calls', True)]:
            self.assertFalse(read_stream(self.stream(finish, done), time.monotonic(), 'test')['ok'])

    def test_error_rejected(self):
        self.assertFalse(read_stream([b'data: {"error":{}}', b'data: [DONE]'], time.monotonic(), 'test')['ok'])


if __name__ == '__main__':
    unittest.main()
