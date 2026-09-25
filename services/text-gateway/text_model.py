"""通过既有 Sub2API 的 Responses 流取得已完整结束的文字决策。"""
import json
import base64
from pathlib import Path
import time
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parent
DEFAULT_INSTRUCTIONS="你是游戏角色决策接口。只输出一个有效 JSON 对象，不加 Markdown 或其他文字。依据角色上下文选择行动，并通过提供的技能调用字段提交给游戏执行；实际结果以世界反馈为准。"

def complete(prompt, config=None, images=None):
    if config is None:
        path=ROOT/'runtime/text_model.json'
        if not path.exists(): return {'ok':False,'error':'未配置文字模型'}
        config=json.loads(path.read_text(encoding='utf-8'))
    started=time.monotonic()
    result=_complete_once(prompt, config, images)
    result.setdefault('model',config['model'])
    result.setdefault('elapsed_ms',round((time.monotonic()-started)*1000))
    fallback=config.get('fallback')
    if result.get('ok') or not result.get('retryable',False) or not fallback:
        return result
    # 只重做尚未交付的模型生成；不重放游戏动作，不递归切换。
    first={'model':config['model'],'error':result['error']}
    result=_complete_once(prompt, fallback, images)
    result.setdefault('model',fallback['model'])
    result['fallback_from']=first
    result['elapsed_ms']=round((time.monotonic()-started)*1000)
    return result


def _complete_once(prompt, config=None, images=None):
    started=time.monotonic()
    first_event_ms=None
    first_text_ms=None
    # 只记录协议元数据，不保存台词、提示词或凭据。
    stream={'event_count':0,'last_event_type':'','text_chars':0,'end':'eof'}
    if config is None:
        path=ROOT/'runtime/text_model.json'
        if not path.exists(): return {'ok':False,'error':'未配置 Sub2API 文字模型'}
        config=json.loads(path.read_text(encoding='utf-8'))
    if config.get('protocol')=='codex_cli':
        import sys
        sys.path.insert(0,str(ROOT.parent/'skill-runtime'))
        from codex_process import text as codex_text
        return codex_text(prompt,config,images)
    if images and config.get('protocol') in ('deepseek_chat','gemini'):
        return {'ok':False,'error':'当前文字协议未接入图片审查，不能跳过视觉验证'}
    if config.get('protocol')=='deepseek_chat':
        from chat_model import complete as chat_complete
        return chat_complete(prompt,config)
    deadline_seconds=config.get('total_timeout_seconds',100)
    if not isinstance(deadline_seconds,(int,float)) or not 10<=deadline_seconds<=240:
        return {'ok':False,'error':'文字模型请求时限配置无效（10至240秒）'}
    payload={'model':config['model'],'stream':True,'store':False,
             'instructions':config.get('instructions',DEFAULT_INSTRUCTIONS),
             'input':[{'role':'user','content':[{'type':'input_text','text':prompt}]}],
             'reasoning':{'effort':config.get('reasoning_effort','low')}}
    if images:
        if len(images)>16:return {'ok':False,'error':'视觉审查图片超过16张'}
        for file in images:
            image=Path(file).read_bytes()
            if len(image)>1500000:return {'ok':False,'error':'视觉审查单帧过大'}
            payload['input'][0]['content'].append({'type':'input_image','image_url':'data:image/jpeg;base64,'+base64.b64encode(image).decode('ascii'),'detail':'high'})
    if config.get('protocol')=='gemini':
        payload={'systemInstruction':{'parts':[{'text':config.get('instructions',DEFAULT_INSTRUCTIONS)}]},
                 'contents':[{'role':'user','parts':[{'text':prompt}]}],
                 'generationConfig':{'responseMimeType':'application/json','maxOutputTokens':1500}}
    request=urllib.request.Request(config['url'],data=json.dumps(payload).encode('utf-8'),headers={
        'Authorization':'Bearer '+config['key'],'Content-Type':'application/json','Accept':'text/event-stream',
        'User-Agent':'Leader-Prototype/0.1'})
    try:
        # 使用本机网络路径，不隐式继承 Windows 浏览器应用代理。
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request,timeout=config.get('read_timeout_seconds',80)) as response:
            gemini_text=''
            for raw in response:
                if time.monotonic()-started > deadline_seconds:
                    return {'ok':False,'error':f'文字模型请求超过{deadline_seconds}秒总时限',
                            'elapsed_ms':round((time.monotonic()-started)*1000),
                            'first_event_ms':first_event_ms,'first_text_ms':first_text_ms,
                            'timeout_kind':'total','retryable':True,'stream_diagnostic':{**stream,'end':'total_timeout'}}
                if not raw.startswith(b'data:'): continue
                data=raw[5:].strip()
                if data==b'[DONE]':
                    stream['end']='done_marker'
                    break
                event=json.loads(data)
                kind=event.get('type','')
                stream['event_count']+=1
                stream['last_event_type']=kind if kind.startswith('response.') or kind=='error' else 'other'
                if kind=='response.output_text.delta':
                    stream['text_chars']+=len(event.get('delta',''))
                if first_event_ms is None:
                    first_event_ms=round((time.monotonic()-started)*1000)
                if event.get('type')=='response.output_text.delta' and event.get('delta') and first_text_ms is None:
                    first_text_ms=round((time.monotonic()-started)*1000)
                if config.get('protocol')=='gemini':
                    candidates=event.get('candidates',[])
                    for candidate in candidates:
                        gemini_text+=''.join(p.get('text','') for p in candidate.get('content',{}).get('parts',[]) if not p.get('thought'))
                        finish=candidate.get('finishReason')
                        if finish=='STOP' and gemini_text:
                            return {'ok':True,'text':gemini_text,'model':event.get('modelVersion',config['model']),
                                    'usage':event.get('usageMetadata',{}),'completion':'STOP',
                                    'elapsed_ms':round((time.monotonic()-started)*1000)}
                        if finish and finish!='STOP': return {'ok':False,'error':'文字模型输出未完整结束：'+finish}
                    continue
                if event.get('type')=='response.completed':
                    result=event['response']
                    if result.get('status')!='completed':
                        return {'ok':False,'error':'文字模型响应未完整结束'}
                    text=''.join(part.get('text','') for item in result.get('output',[]) if item.get('type')=='message'
                                 for part in item.get('content',[]) if part.get('type')=='output_text')
                    if not text: return {'ok':False,'error':'文字模型没有返回内容'}
                    return {'ok':True,'text':text,'model':result.get('model',config['model']),
                            'usage':result.get('usage',{}),'completion':'response.completed',
                            'first_event_ms':first_event_ms,'first_text_ms':first_text_ms,
                            'elapsed_ms':round((time.monotonic()-started)*1000)}
                if event.get('type') in ['response.failed','response.incomplete','error']:
                    return {'ok':False,'error':'文字模型返回失败或不完整响应',
                            'stream_diagnostic':dict(stream,end='failure_event')}
        return {'ok':False,'error':'文字模型流结束但缺少 response.completed','retryable':True,
                'stream_diagnostic':stream,'first_event_ms':first_event_ms,'first_text_ms':first_text_ms}
    except urllib.error.HTTPError as exc:
        detail=exc.read(2000).decode('utf-8',errors='replace').replace(config['key'],'[redacted]')
        return {'ok':False,'error':'Sub2API 文字模型 HTTP '+str(exc.code),'diagnostic':detail[:500],'retryable':exc.code in (408,429,500,502,503,504)}
    except TimeoutError:
        return {'ok':False,'error':'文字模型连接或连续读取超时',
                'elapsed_ms':round((time.monotonic()-started)*1000),
                'first_event_ms':first_event_ms,'first_text_ms':first_text_ms,'timeout_kind':'connection_or_read','retryable':True}
    except OSError:
        return {'ok':False,'error':'文字模型网络连接失败','retryable':True}
    except ValueError:
        return {'ok':False,'error':'Sub2API 文字模型网络或协议错误'}
