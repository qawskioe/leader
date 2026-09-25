"""官方 Gemini TTS 免费项目的小规模验证；不使用 Live，不自动换模型或重试。"""
import argparse
import base64
import json
from pathlib import Path
import time
import urllib.error
import urllib.request
import wave

ROOT=Path(__file__).resolve().parent
MODEL='gemini-3.1-flash-tts-preview'
LINE='好，我听你的。食物先给她，我再等等。'
STYLES={
    'neutral':'自然平静地说话。',
    'restrained':'语气冷淡，压着怨气，勉强服从，不情愿但不敢争辩。收着声音，不撒娇，不用哭腔，不大喊。',
    'angry':'明显生气，语气坚定而恼火。像真人对眼前的人说话，不使用播音腔。',
}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise RuntimeError('拒绝携带密钥重定向')

def events(response):
    pending=[];name=''
    for raw in response:
        line=raw.decode('utf-8').rstrip('\r\n')
        if line.startswith('event:'):name=line[6:].strip()
        elif line.startswith('data:'):pending.append(line[5:].lstrip())
        elif not line and pending:
            data='\n'.join(pending);pending=[]
            if data.strip()=='[DONE]':return
            value=json.loads(data)
            value.setdefault('event_type',name)
            yield value
    if pending:
        data='\n'.join(pending)
        if data.strip()=='[DONE]':return
        value=json.loads(data);value.setdefault('event_type',name);yield value

def run(style):
    key=(ROOT/'runtime/api-key.txt').read_text(encoding='utf-8').strip()
    prompt=('请执行中文语音合成，仅朗读下方 Transcript 的原文。表达要求只用于调整声音，不得读出要求、标题或增加台词。\n'
            'Director notes: '+STYLES[style]+'\nTranscript:\n'+LINE)
    body={'model':MODEL,'input':prompt,'response_format':{'type':'audio'},
          'generation_config':{'speech_config':[{'voice':'Kore'}]},'stream':True,'store':False}
    req=urllib.request.Request('https://generativelanguage.googleapis.com/v1beta/interactions',
          data=json.dumps(body).encode('utf-8'),headers={'x-goog-api-key':key,'Content-Type':'application/json','Accept':'text/event-stream'})
    result={'model':MODEL,'voice':'Kore','style':style,'text':LINE,'instruction':STYLES[style],
            'billing_tier':'Free Tier, confirmed by user','passed':False}
    started=time.perf_counter();pcm=bytearray();first=None;chunks=0;done=False;trace=[]
    try:
        with urllib.request.build_opener(NoRedirect()).open(req,timeout=90) as response:
            for event in events(response):
                elapsed=round((time.perf_counter()-started)*1000)
                kind=event.get('event_type');delta=event.get('delta',{})
                record={'event':kind,'elapsed_ms':elapsed}
                if kind=='step.delta' and delta.get('type')=='audio':
                    data=base64.b64decode(delta['data'],validate=True)
                    mime=delta.get('mime_type','')
                    if mime and mime.split(';',1)[0].lower() not in {'audio/l16','audio/pcm'}:raise RuntimeError('非预期音频格式：'+mime)
                    if len(data)%2:raise RuntimeError('PCM 字节数无效')
                    if data:
                        if first is None:first=elapsed
                        pcm.extend(data);chunks+=1
                    record.update(audio_bytes=len(data),mime=mime)
                elif kind=='interaction.completed':
                    if event.get('interaction',{}).get('status')!='completed':
                        raise RuntimeError('交互结束状态不是 completed')
                    done=True
                    result['completion']=event
                elif kind in ['error','interaction.failed','interaction.cancelled']:
                    raise RuntimeError(json.dumps(event,ensure_ascii=False))
                trace.append(record)
        if not done or not pcm:raise RuntimeError('缺少音频或明确的完成标记')
        path=ROOT/'runtime'/('sample_'+style+'.wav')
        with wave.open(str(path),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(24000);wav.writeframes(pcm)
        result.update(passed=True,file=str(path),chunks=chunks,first_audio_ms=first,
                      total_ms=round((time.perf_counter()-started)*1000),audio_seconds=len(pcm)/48000)
    except urllib.error.HTTPError as error:
        result.update(http_status=error.code,error=error.read(12000).decode(errors='replace').replace(key,'[redacted]'))
    except Exception as error:
        result['error']=str(error).replace(key,'[redacted]')
    result['trace']=trace
    (ROOT/'runtime'/('result_'+style+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ['trace','completion']},ensure_ascii=True),flush=True)
    return result['passed']

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('style',choices=STYLES)
    raise SystemExit(0 if run(parser.parse_args().style) else 1)
