"""验证中断的生成永远不能当作完整决策交付，诊断不包含台词。"""
import io
import json
import unittest
from unittest.mock import Mock, patch
import text_model

class ResponseStreamTests(unittest.TestCase):
    config={'url':'http://localhost/responses','key':'test-secret','model':'test'}

    def run_stream(self, events, done=False, config=None):
        wire=b''.join(b'data: '+json.dumps(e).encode()+b'\n\n' for e in events)
        if done:
            wire+=b'data: [DONE]\n\n'
        opener=Mock()
        opener.open.return_value=io.BytesIO(wire)
        with patch.object(text_model.urllib.request,'build_opener',return_value=opener):
            result=text_model.complete('private-prompt',self.config if config is None else config)
        self.requests=[json.loads(call.args[0].data) for call in opener.open.call_args_list]
        return result

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

    def test_fast_requests_priority_without_changing_model_or_reasoning(self):
        result=self.run_stream([{'type':'response.completed','response':{
            'status':'completed','service_tier':'priority','output':[{'type':'message',
                'content':[{'type':'output_text','text':'{}'}]}]}}],
            config={**self.config,'service_tier':'fast','reasoning_effort':'medium'})
        self.assertTrue(result['ok'])
        self.assertEqual(self.requests[0]['service_tier'],'priority')
        self.assertEqual(self.requests[0]['model'],'test')
        self.assertEqual(self.requests[0]['reasoning'],{'effort':'medium'})
        self.assertEqual(result['requested_service_tier'],'priority')
        self.assertEqual(result['service_tier'],'priority')

    def test_reported_tier_is_not_inferred_from_requested_tier(self):
        for actual in ('default',None):
            with self.subTest(actual=actual):
                response={'status':'completed','output':[{'type':'message',
                    'content':[{'type':'output_text','text':'{}'}]}]}
                if actual is not None:response['service_tier']=actual
                result=self.run_stream([{'type':'response.completed','response':response}],
                    config={**self.config,'service_tier':'priority'})
                self.assertTrue(result['ok'])
                self.assertEqual(result['requested_service_tier'],'priority')
                self.assertEqual(result['service_tier'],actual)

    def test_invalid_tier_fails_before_network(self):
        result=self.run_stream([],config={**self.config,'service_tier':'turbo'})
        self.assertFalse(result['ok'])
        self.assertEqual(self.requests,[])

    def test_gemini_failure_keeps_usage_and_reason_without_partial_text_or_retry(self):
        cfg={**self.config,'protocol':'gemini','fallback':self.config}
        usage={'promptTokenCount':23000,'thoughtsTokenCount':8180,'candidatesTokenCount':12,'totalTokenCount':31192}
        for reason in ('MAX_TOKENS','MALFORMED_FUNCTION_CALL'):
            with self.subTest(reason=reason):
                events=[{'modelVersion':'gemini-actual','candidates':[{'content':{'parts':[{'thought':True,'text':'private-thought'}]}}]},
                    {'modelVersion':'gemini-actual','candidates':[{'content':{'parts':[{'text':'{"reply":"private-reply"'}]},'finishReason':reason}],
                     'usageMetadata':usage}]
                result=self.run_stream(events,config=cfg)
                self.assertFalse(result['ok'])
                self.assertEqual(result['completion'],reason)
                self.assertEqual(result['model'],'gemini-actual')
                self.assertEqual(result['usage'],usage)
                self.assertFalse(result['retryable'])
                self.assertNotIn('fallback_from',result,'预算或格式错误不能自动消耗第二次生成')
                self.assertNotIn('text',result)
                self.assertEqual(result['stream_diagnostic']['text_chars'],24)
                self.assertEqual(result['stream_diagnostic']['end'],reason)
                self.assertIsNotNone(result['first_event_ms'])
                self.assertIsNotNone(result['first_text_ms'])
                for private in ('private-prompt','private-thought','private-reply','test-secret'):
                    self.assertNotIn(private,json.dumps(result))

    def test_gemini_success_reports_actual_text_latency(self):
        cfg={**self.config,'protocol':'gemini'}
        result=self.run_stream([
            {'candidates':[{'content':{'parts':[{'thought':True,'text':'private-thought'}]}}]},
            {'candidates':[{'content':{'parts':[{'text':'{}'}]},'finishReason':'STOP'}]}],config=cfg)
        self.assertTrue(result['ok'])
        self.assertEqual(result['text'],'{}')
        self.assertIsNotNone(result['first_event_ms'])
        self.assertIsNotNone(result['first_text_ms'])

if __name__=='__main__':unittest.main()
