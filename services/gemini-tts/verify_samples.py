"""三句不同台词经正式本机流接口合成，再由 CapsWriter 回听检查；不自动重试。"""
import asyncio
from array import array
import base64
import json
from pathlib import Path
import time
import urllib.request
import uuid
import wave

import websockets

ROOT = Path(__file__).resolve().parent
SAMPLES = [
    ('neutral', '洞口的木柴已经搬好了。我先去取水，回来再照看火堆。'),
    ('restrained', '好，先给她吧。我也忙了一整天，不过，我还能再等一会儿。'),
    ('angry', '别再往里走了！那边的石头正在往下掉，快回来！'),
]


async def transcribe(pcm):
    values = array('h', pcm)
    # 24k → 16k 线性重采样，仅供合成样本回听验证。
    floats = array('f')
    for index in range(len(values) * 2 // 3):
        pos = index * 1.5
        lo = int(pos)
        hi = min(lo + 1, len(values) - 1)
        floats.append((values[lo] + (values[hi] - values[lo]) * (pos - lo)) / 32768)
    task_id = str(uuid.uuid4())
    async with websockets.connect('ws://127.0.0.1:6016', subprotocols=['binary'], max_size=2**20) as ws:
        await ws.send(json.dumps({'task_id':task_id,'source':'mic','data':base64.b64encode(floats.tobytes()).decode(),
                                  'is_final':True,'time_start':time.time(),'seg_duration':30,'seg_overlap':0,'context':'','language':'Chinese'}))
        async with asyncio.timeout(30):
            async for raw in ws:
                value = json.loads(raw)
                if value.get('task_id') == task_id and value.get('is_final'):
                    return value.get('text', '')
    raise RuntimeError('CapsWriter 未返回完成转写')


def run():
    key = (ROOT / 'runtime/gateway-key.txt').read_text(encoding='utf-8').strip()
    results = []
    for style, text in SAMPLES:
        started = time.monotonic()
        request = urllib.request.Request('http://127.0.0.1:18092/speak',
                  data=json.dumps({'text':text,'style':style,'voice':'Kore'}).encode(),
                  headers={'Content-Type':'application/json','Authorization':'Bearer '+key})
        pcm = bytearray(); first = None; sequence = 0; done = False
        with urllib.request.urlopen(request, timeout=100) as response:
            for raw in response:
                event = json.loads(raw)
                if event['type'] == 'audio':
                    if event['sequence'] != sequence:
                        raise RuntimeError('音频乱序')
                    if first is None: first = round((time.monotonic()-started)*1000)
                    pcm.extend(base64.b64decode(event['pcm_base64'],validate=True)); sequence += 1
                elif event['type'] == 'done':
                    if event['chunks'] != sequence or event['audio_bytes'] != len(pcm):
                        raise RuntimeError('完成标记数量不符')
                    done = True
                else: raise RuntimeError(event.get('error','未知消息'))
        if not done or not pcm: raise RuntimeError('缺少完成标记或音频')
        elapsed = round((time.monotonic()-started)*1000)
        path = ROOT / 'runtime' / f'varied_{style}.wav'
        with wave.open(str(path),'wb') as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(24000); output.writeframes(pcm)
        recognized = asyncio.run(transcribe(pcm))
        result = {'style':style,'text':text,'transcript':recognized,'voice':'Kore',
                  'file':str(path),'first_audio_ms':first,'generation_ms':elapsed,
                  'audio_seconds':len(pcm)/48000,'chunks':sequence,'stream_completed':done}
        results.append(result)
        print(json.dumps(result,ensure_ascii=True),flush=True)
        (ROOT/'runtime/varied_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    return results


if __name__ == '__main__': run()
