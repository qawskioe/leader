"""同台词、同音色、同表达指令比较两个 Cloud TTS 模型，不改变游戏模型。"""
import asyncio
import base64
import json
import time
import wave
from pathlib import Path

import grpc
import cloud_provider as cloud
from verify_samples import transcribe

ROOT = Path(__file__).resolve().parent
MODELS = ['gemini-3.1-flash-tts-preview','gemini-2.5-pro-tts']
LINE = '好，我听你的。食物先给她，我再等等。'


def run():
    cloud.prepare()
    client = cloud.get_client(cloud.load_config())
    grpc.channel_ready_future(client.transport.grpc_channel).result(timeout=15)
    results = []
    for model in MODELS:
        cloud.MODEL = model  # 仅此比较脚本进程，不修改游戏服务。
        started = time.monotonic(); first = None; pcm = bytearray(); done = False
        for packet in cloud.synthesize({'text':LINE,'style':'restrained','voice':'Kore'}):
            if packet['type'] == 'audio':
                if first is None: first = round((time.monotonic()-started)*1000)
                pcm.extend(base64.b64decode(packet['pcm_base64'],validate=True))
            elif packet['type'] == 'done': done = True
        if not done: raise RuntimeError('未完整生成：'+model)
        elapsed = round((time.monotonic()-started)*1000)
        path = ROOT/'runtime'/('compare_'+model+'.wav')
        with wave.open(str(path),'wb') as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(24000); output.writeframes(pcm)
        transcript = asyncio.run(transcribe(pcm))
        result = {'model':model,'voice':'Kore','style':'restrained','instruction':cloud.STYLES['restrained'],
                  'text':LINE,'file':str(path),'first_audio_ms':first,'generation_ms':elapsed,
                  'audio_seconds':len(pcm)/48000,'transcript':transcript,'completed':done}
        results.append(result)
        (ROOT/'runtime/model_comparison.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=True),flush=True)


if __name__ == '__main__':run()
