import json
import unittest
from unittest.mock import patch
import text_model

class FallbackTests(unittest.TestCase):
    config={'model':'luna','fallback':{'model':'deepseek'}}
    def test_transient_failure_preserves_prompt_and_switches_once(self):
        with patch.object(text_model,'_complete_once',side_effect=[{'ok':False,'error':'HTTP 503','retryable':True},{'ok':True,'text':'{}','model':'deepseek'}]) as call:
            result=text_model.complete('original',self.config)
            self.assertTrue(result['ok'])
            self.assertEqual(result['fallback_from']['model'],'luna')
            self.assertEqual(call.call_args_list[1].args,('original',self.config['fallback'],None))
            self.assertEqual(call.call_count,2)
    def test_success_or_permanent_error_does_not_switch(self):
        for result in [{'ok':True,'text':'{}'},{'ok':False,'error':'HTTP 401','retryable':False},{'ok':False,'error':'invalid output'}]:
            with patch.object(text_model,'_complete_once',return_value=result) as call:
                self.assertEqual(text_model.complete('x',self.config),result)
                self.assertEqual(call.call_count,1)
    def test_fallback_failure_does_not_loop(self):
        with patch.object(text_model,'_complete_once',return_value={'ok':False,'error':'timeout','retryable':True}) as call:
            self.assertFalse(text_model.complete('x',self.config)['ok'])
            self.assertEqual(call.call_count,2)
    def test_failure_keeps_both_provider_identities(self):
        with patch.object(text_model,'_complete_once',side_effect=[{'ok':False,'error':'HTTP 503','retryable':True},{'ok':False,'error':'DeepSeek HTTP 402','retryable':False}]):
            result=text_model.complete('x',self.config)
            self.assertEqual(result['model'],'deepseek')
            self.assertEqual(result['fallback_from'],{'model':'luna','error':'HTTP 503'})
            self.assertEqual(result['error'],'DeepSeek HTTP 402')
            self.assertGreaterEqual(result['elapsed_ms'],0)
    def test_attempt_diagnostics_keep_independent_waits_and_unknown_usage(self):
        clock=[10.0]
        replies=iter([
            {'ok':False,'error':'total timeout','retryable':True,'timeout_kind':'total',
             'first_event_ms':12,'first_text_ms':None,'stream_diagnostic':{'end':'total_timeout','text_chars':0},'diagnostic':'private_body'},
            {'ok':True,'text':'private_reply','model':'deepseek','usage':{'input_tokens':100,'output_tokens':7,
             'input_tokens_details':{'cached_tokens':0},'output_tokens_details':{'reasoning_tokens':0},'attribution':{'private_payload':1}}}])
        def complete_once(*args,**kwargs):
            clock[0]+=.125 if args[1]['model']=='luna' else .375
            return next(replies)
        with patch.object(text_model,'_complete_once',side_effect=complete_once) as call, patch.object(text_model.time,'monotonic',side_effect=lambda:clock[0]):
            result=text_model.complete('private_prompt',self.config)
        attempts=result['attempts']
        self.assertEqual(call.call_count,2)
        self.assertEqual(result['elapsed_ms'],500)
        self.assertEqual([item['role'] for item in attempts],['primary','fallback'])
        self.assertEqual([item['elapsed_ms'] for item in attempts],[125,375])
        self.assertEqual([item['requested_model'] for item in attempts],['luna','deepseek'])
        self.assertIsNone(attempts[0]['usage'])
        self.assertEqual(attempts[0]['timeout_kind'],'total')
        self.assertEqual(attempts[0]['first_event_ms'],12)
        self.assertIsNone(attempts[0]['first_text_ms'])
        self.assertEqual(attempts[1]['usage'],{'input_tokens':100,'output_tokens':7,'input_tokens_details':{'cached_tokens':0},'output_tokens_details':{'reasoning_tokens':0}})
        self.assertNotIn('private_',json.dumps(attempts))
    def test_single_attempt_and_double_failure_remain_bounded(self):
        for replies,expected in [([{'ok':True,'text':'{}'}],1),([{'ok':False,'error':'invalid config'}],1),([{'ok':False,'error':'network','retryable':True},{'ok':False,'error':'timeout','retryable':True}],2)]:
            with patch.object(text_model,'_complete_once',side_effect=replies) as call:
                result=text_model.complete('x',self.config)
            self.assertEqual(call.call_count,expected)
            self.assertEqual(len(result['attempts']),expected)
            self.assertTrue(all(item['usage'] is None for item in result['attempts']))
if __name__=='__main__':unittest.main()
