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
if __name__=='__main__':unittest.main()
