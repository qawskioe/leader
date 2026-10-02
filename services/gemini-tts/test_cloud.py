"""Cloud 接入检查全部模拟，不消耗任何云端额度。"""
from datetime import datetime, timedelta, timezone
import json
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import cloud_provider as cloud


class CloudTests(unittest.TestCase):
    def test_client_reuse_and_expiry_blocks_network(self):
        config = {'project_id':'p','account':'a','gcloud_script':'gcloud.py'}
        with patch.object(cloud,'_client',None), patch.object(cloud,'_client_identity',None), patch.object(cloud.texttospeech,'TextToSpeechClient') as factory:
            self.assertIs(cloud.get_client(config),cloud.get_client(config))
            self.assertEqual(factory.call_count,1)
        with patch.object(cloud,'load_config',side_effect=ValueError('expired')), patch.object(cloud,'get_client') as network:
            with self.assertRaises(ValueError):
                list(cloud.synthesize({'text':'好','style':'neutral','voice':'Kore'}))
            network.assert_not_called()

    def test_public_input_and_pcm_config(self):
        parts = list(cloud.requests_for({'text':'好，我听你的。','style':'温和但不撒娇，语速稍慢，最后一句坚定','voice':'Kore'}))
        self.assertEqual(len(parts),2)
        self.assertEqual(parts[0].streaming_config.voice.model_name,cloud.MODEL)
        self.assertEqual(parts[0].streaming_config.voice.language_code,'cmn-CN')
        self.assertEqual(parts[0].streaming_config.streaming_audio_config.sample_rate_hertz,24000)
        self.assertEqual(parts[1].input.text,'好，我听你的。')
        self.assertIn('温和但不撒娇，语速稍慢，最后一句坚定',parts[1].input.prompt)

    def test_rpc_success_and_fragmented_pcm(self):
        values = [SimpleNamespace(audio_content=b'\0'),SimpleNamespace(audio_content=b'\0'*4801)]
        result = list(cloud.packets_for(values))
        self.assertEqual(result[-1],{'type':'done','chunks':2,'audio_bytes':4802})

    def test_truncated_rpc_never_done(self):
        def broken():
            yield SimpleNamespace(audio_content=b'\0\0')
            raise RuntimeError('broken stream')
        stream = cloud.packets_for(broken())
        self.assertEqual(next(stream)['type'],'audio')
        with self.assertRaises(RuntimeError): next(stream)
        for values in [[],[SimpleNamespace(audio_content=b'\0')]]:
            with self.assertRaises(ValueError):list(cloud.packets_for(values))

    def test_unconfirmed_and_expired_config(self):
        valid = {'project_id':'p','account':'a','gcloud_script':__file__,
                 'trial_credit_confirmed':True,'stop_at_utc':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}
        with patch.object(cloud.Path,'is_file',return_value=True):
            for changes in [{'trial_credit_confirmed':False},{'stop_at_utc':'2000-01-01T00:00:00Z'}]:
                with patch.object(cloud.Path,'read_text',return_value=json.dumps(valid|changes)), self.assertRaises(ValueError):
                    cloud.load_config()
            with patch.object(cloud.Path,'read_text',return_value=json.dumps(valid)):
                self.assertEqual(cloud.load_config()['project_id'],'p')


if __name__ == '__main__':unittest.main(verbosity=2)
