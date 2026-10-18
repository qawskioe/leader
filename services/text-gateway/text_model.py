"""通过既有 Sub2API 的 Responses 流取得已完整结束的文字决策。"""
import json
import base64
from pathlib import Path
import time
import urllib.error
import urllib.request
from context_cache import CACHE, ENCODING

ROOT=Path(__file__).resolve().parent
DEFAULT_INSTRUCTIONS="你是游戏角色决策接口。只输出一个有效 JSON 对象，不加 Markdown 或其他文字。依据角色上下文选择行动，并通过提供的技能调用字段提交给游戏执行；实际结果以世界反馈为准。"

def _attempt_summary(result, config, role, elapsed_ms):
    # 证明适配器调用及其返回；配置校验失败不代表已经发出网络请求。缺失用量不补零。
    raw=result.get('usage')
    usage={key:value for key,value in raw.items() if isinstance(value,(int,float)) and not isinstance(value,bool)} if isinstance(raw,dict) else {}
    for key in ('input_tokens_details','output_tokens_details','prompt_tokens_details','completion_tokens_details'):
        detail=raw.get(key) if isinstance(raw,dict) else None
        if isinstance(detail,dict):
            counts={name:value for name,value in detail.items() if isinstance(value,(int,float)) and not isinstance(value,bool)}
            if counts:usage[key]=counts
    stream=result.get('stream_diagnostic')
    return {'role':role,'requested_model':config['model'],'model':result.get('model'),
            'ok':result['ok'],'elapsed_ms':elapsed_ms,'error':result.get('error'),
            'timeout_kind':result.get('timeout_kind'),'first_event_ms':result.get('first_event_ms'),
            'first_text_ms':result.get('first_text_ms'),
            'stream_diagnostic':{key:stream[key] for key in ('event_count','last_event_type','text_chars','end') if key in stream} if isinstance(stream,dict) else None,
            'usage':usage or None}

def complete(prompt, config=None, images=None, prefix='', reference='', context_scope=''):
    if config is None:
        path=ROOT/'runtime/text_model.json'
        if not path.exists(): return {'ok':False,'error':'未配置文字模型'}
        config=json.loads(path.read_text(encoding='utf-8'))
    started=time.monotonic()
    result=_complete_once(prompt, config, images, prefix=prefix, reference=reference, context_scope=context_scope)
    elapsed_ms=round((time.monotonic()-started)*1000)
    attempts=[_attempt_summary(result,config,'primary',elapsed_ms)]
    result['attempts']=attempts
    result.setdefault('model',config['model'])
    result.setdefault('elapsed_ms',elapsed_ms)
    fallback=config.get('fallback')
    if result.get('ok') or not result.get('retryable',False) or not fallback:
        return result
    # 只重做尚未交付的模型生成；不重放游戏动作，不递归切换。
    first={'model':config['model'],'error':result['error']}
    attempt_started=time.monotonic()
    result=_complete_once(prompt, fallback, images, prefix=prefix, reference=reference, context_scope=context_scope)
    attempts.append(_attempt_summary(result,fallback,'fallback',round((time.monotonic()-attempt_started)*1000)))
    result['attempts']=attempts
    result.setdefault('model',fallback['model'])
    result['fallback_from']=first
    result['elapsed_ms']=round((time.monotonic()-started)*1000)
    return result


def _complete_once(prompt, config=None, images=None, prefix='', reference='', context_scope=''):
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
        return codex_text('\n\n'.join(part for part in (prefix,reference,prompt) if part),config,images)
    if images and config.get('protocol') in ('deepseek_chat','gemini'):
        return {'ok':False,'error':'当前文字协议未接入图片审查，不能跳过视觉验证'}
    if config.get('protocol')=='deepseek_chat':
        from chat_model import complete as chat_complete
        return chat_complete('\n\n'.join(part for part in (prefix,reference,prompt) if part),config)
    deadline_seconds=config.get('total_timeout_seconds',100)
    if not isinstance(deadline_seconds,(int,float)) or not 10<=deadline_seconds<=240:
        return {'ok':False,'error':'文字模型请求时限配置无效（10至240秒）'}
    payload={'model':config['model'],'stream':True,'store':False,
             'instructions':config.get('instructions',DEFAULT_INSTRUCTIONS),
             'input':[{'role':'user','content':[{'type':'input_text','text':prompt}]}],
             'reasoning':{'effort':config.get('reasoning_effort','low')}}
    cache_mode=config.get('context_cache',False)
    if not isinstance(cache_mode,bool):
        return {'ok':False,'error':'context_cache配置必须为布尔值'}
    cache_packet=None
    if cache_mode and config.get('protocol')!='gemini' and not images and prefix and reference:
        cache_packet=CACHE.prepare(prompt,prefix,reference,dict(config,context_scope=context_scope))
        if cache_packet:
            payload['input']=[{'role':'user','content':[{'type':'input_text','text':text}]} for text in cache_packet['messages']]
            payload['prompt_cache_key']=cache_packet['key']
            prefix=prefix+'\n\n'+ENCODING
    # 首次完整现场成为缓存写入边界；更新只覆盖本人现场，不追加其他人的历史。
    if reference:payload['input'].insert(0,{'role':'user','content':[{'type':'input_text','text':reference}]})
    if prefix:payload['input'].insert(0,{'role':'developer','content':[{'type':'input_text','text':prefix}]})
    if config.get('protocol')!='gemini' and 'service_tier' in config:
        tier=config['service_tier']
        if tier not in ('auto','default','flex','priority','fast'):
            return {'ok':False,'error':'Responses服务档位配置无效'}
        # Fast使用上游Responses的priority档位；模型及思考程度保持原配置。
        payload['service_tier']='priority' if tier=='fast' else tier
    if images:
        if len(images)>16:return {'ok':False,'error':'视觉审查图片超过16张'}
        for file in images:
            image=Path(file).read_bytes()
            if len(image)>1500000:return {'ok':False,'error':'视觉审查单帧过大'}
            payload['input'][-1]['content'].append({'type':'input_image','image_url':'data:image/jpeg;base64,'+base64.b64encode(image).decode('ascii'),'detail':'high'})
    if config.get('protocol')=='gemini':
        output_budget=config.get('max_output_tokens',1500)
        if not isinstance(output_budget,int) or isinstance(output_budget,bool) or not 128<=output_budget<=32768:
            return {'ok':False,'error':'Gemini输出预算配置无效（128至32768 token）'}
        instructions='\n\n'.join(part for part in (config.get('instructions',DEFAULT_INSTRUCTIONS),prefix) if part)
        payload={'systemInstruction':{'parts':[{'text':instructions}]},
                 'contents':[{'role':'user','parts':[{'text':'\n\n'.join(part for part in (reference,prompt) if part)}]}],
                 'generationConfig':{'responseMimeType':'application/json','maxOutputTokens':output_budget}}
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
                        delta=''.join(p.get('text','') for p in candidate.get('content',{}).get('parts',[]) if not p.get('thought'))
                        gemini_text+=delta
                        stream['text_chars']+=len(delta)
                        if delta and first_text_ms is None:
                            first_text_ms=round((time.monotonic()-started)*1000)
                        finish=candidate.get('finishReason')
                        metadata={'model':event.get('modelVersion',config['model']),
                                  'usage':event.get('usageMetadata',{}),'completion':finish,
                                  'first_event_ms':first_event_ms,'first_text_ms':first_text_ms,
                                  'stream_diagnostic':dict(stream,end=finish or 'streaming')}
                        if finish=='STOP' and gemini_text:
                            return {'ok':True,'text':gemini_text,**metadata,
                                    'elapsed_ms':round((time.monotonic()-started)*1000)}
                        if finish and finish!='STOP':
                            # 保留上游用量和结束原因，不交付半截决策，也不自动重试格式/预算失败。
                            return {'ok':False,'error':'文字模型输出未完整结束：'+finish,
                                    'retryable':False,**metadata}
                    continue
                if event.get('type')=='response.completed':
                    result=event['response']
                    if result.get('status')!='completed':
                        return {'ok':False,'error':'文字模型响应未完整结束'}
                    text=''.join(part.get('text','') for item in result.get('output',[]) if item.get('type')=='message'
                                 for part in item.get('content',[]) if part.get('type')=='output_text')
                    if not text: return {'ok':False,'error':'文字模型没有返回内容'}
                    if cache_packet:
                        usage=result.get('usage',{})
                        if cache_packet['diagnostic']['mode']=='base':
                            tokens=usage.get('input_tokens') if isinstance(usage,dict) and len(cache_packet['messages'])==1 else None
                            CACHE.confirm(cache_packet['key'],cache_packet['diagnostic']['base_id'],tokens)
                        else:
                            details=usage.get('input_tokens_details',{}) if isinstance(usage,dict) else {}
                            cached=details.get('cached_tokens') if isinstance(details,dict) else None
                            if CACHE.observe_miss(cache_packet['key'],cache_packet['diagnostic']['base_id'],cached):
                                cache_packet['diagnostic']['rebase_next']=True
                    return {'ok':True,'text':text,'model':result.get('model',config['model']),
                            'usage':result.get('usage',{}),'completion':'response.completed',
                            'requested_service_tier':payload.get('service_tier'),
                            'service_tier':result.get('service_tier'),
                            'context_cache':cache_packet['diagnostic'] if cache_packet else {},
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
