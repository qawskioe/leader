import io
import asyncio
import sys
import types
import json
import unittest
from unittest.mock import patch
import run
import text_model


class PrefixTests(unittest.TestCase):
    config={'model':'gpt-6.1-sol','url':'https://example.invalid','key':'fixture'}

    def stream(self):
        response={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'{}'}]}],
                  'usage':{'input_tokens':2500,'input_tokens_details':{'cached_tokens':1732,'cache_write_tokens':0}}}
        return io.BytesIO(('data: '+json.dumps({'type':'response.completed','response':response})+'\n').encode())

    def test_messages_preserve_stable_boundaries_and_live_suffix(self):
        sent=[]
        class Opener:
            def open(inner,request,timeout):
                sent.append(json.loads(request.data));return self.stream()
        with patch('text_model.urllib.request.build_opener',return_value=Opener()):
            first=text_model.complete('first scene',self.config,prefix='fixed rules',reference='fixed catalog')
            text_model.complete('second scene',self.config,prefix='fixed rules',reference='fixed catalog')
        self.assertEqual(sent[0]['input'][:2],sent[1]['input'][:2])
        self.assertEqual([m['role'] for m in sent[0]['input']],['developer','user','user'])
        self.assertEqual(sent[1]['input'][-1]['content'][0]['text'],'second scene')
        self.assertEqual(first['usage']['input_tokens_details']['cached_tokens'],1732)

    def test_fallback_keeps_the_same_rules_catalog_and_scene(self):
        cfg=dict(self.config,fallback=dict(self.config,model='gpt-6-luna'))
        with patch('text_model._complete_once',side_effect=[{'ok':False,'error':'503','retryable':True},{'ok':True,'text':'{}'}]) as call:
            result=text_model.complete('scene',cfg,prefix='rules',reference='catalog',context_scope='world')
        self.assertTrue(result['ok'])
        self.assertEqual(call.call_args_list[0].kwargs,call.call_args_list[1].kwargs)
        self.assertEqual(call.call_args_list[1].kwargs,{'prefix':'rules','reference':'catalog','context_scope':'world'})

    def test_gemini_receives_all_parts_without_openai_cache_fields(self):
        wire=b'data: {"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"STOP"}]}\n'
        with patch('text_model.urllib.request.build_opener') as factory:
            factory.return_value.open.return_value=io.BytesIO(wire)
            result=text_model.complete('scene',dict(self.config,protocol='gemini'),prefix='rules',reference='catalog')
            sent=json.loads(factory.return_value.open.call_args.args[0].data)
        self.assertTrue(result['ok'])
        self.assertIn('rules',sent['systemInstruction']['parts'][0]['text'])
        self.assertEqual(sent['contents'][0]['parts'][0]['text'],'catalog\n\nscene')
        self.assertNotIn('prompt_cache_options',sent)

    def test_gateway_validates_and_forwards_structured_context(self):
        body={'mode':'decision','prefix':'rules','reference':'catalog','prompt':'scene','context_scope':'world'}
        with patch('run.authorize'),patch('run.complete',return_value={'ok':True,'text':'{}'}) as call:
            self.assertEqual(self.post(body),200)
            self.assertEqual(call.call_args.args,('scene',))
            self.assertEqual(call.call_args.kwargs,{'prefix':'rules','reference':'catalog','context_scope':'world'})
            call.reset_mock()
            for changed in [dict(body,prefix=42),dict(body,reference='x'*150001),dict(body,prompt='x'*250000),dict(body,context_scope=42),dict(body,context_scope='x'*97)]:
                self.assertEqual(self.post(changed),422)
            call.assert_not_called()

    def test_chat_adapter_preserves_all_sections(self):
        with patch('chat_model.complete',return_value={'ok':True,'text':'{}'}) as call:
            result=text_model.complete('scene',dict(self.config,protocol='deepseek_chat'),prefix='rules',reference='catalog')
        self.assertTrue(result['ok'])
        self.assertEqual(call.call_args.args[0],'rules\n\ncatalog\n\nscene')

    def test_cli_adapter_preserves_all_sections_without_launching(self):
        module=types.SimpleNamespace()
        with patch.object(module,'text',create=True,return_value={'ok':True,'text':'{}'}) as call,patch.dict(sys.modules,{'codex_process':module}):
            result=text_model.complete('scene',dict(self.config,protocol='codex_cli'),prefix='rules',reference='catalog')
        self.assertTrue(result['ok'])
        self.assertEqual(call.call_args.args[0],'rules\n\ncatalog\n\nscene')

    def post(self,body):
        async def exchange():
            messages=[]
            async def receive():return {'type':'http.request','body':json.dumps(body).encode(),'more_body':False}
            async def send(message):messages.append(message)
            scope={'type':'http','http_version':'1.1','method':'POST','scheme':'http','path':'/game/exchange',
                   'raw_path':b'/game/exchange','query_string':b'','headers':[(b'host',b'testserver'),(b'content-type',b'application/json')],
                   'server':('testserver',80),'client':('127.0.0.1',1234)}
            await run.app(scope,receive,send)
            return next(message['status'] for message in messages if message['type']=='http.response.start')
        return asyncio.run(exchange())


if __name__=='__main__':unittest.main()
