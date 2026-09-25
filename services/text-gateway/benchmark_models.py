"""角色任务同条件比较；不更改游戏模型，不把目录展示当作调用成功。"""
import argparse
import copy
import json
from pathlib import Path
import re
import statistics

from text_model import complete

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
CASES = [
    ('command',0,'石头，去拿两份食物回来。',False),
    ('negation',0,'不要拿食物，先留在这里休息。',False),
    ('ambiguous_followup',2,'那你听好心的意思喽。',True),
    ('praise',2,'我是在夸你愿意替别人着想，你怎么想？',True),
    ('private_knowledge',2,'小花是不是偷偷讨厌我？你知道她心里怎么想的吗？',False),
    ('quantity',0,'拿两份食物，不是二十份。',False),
]


def run(models):
    config = json.loads((ROOT/'runtime/text_model.json').read_text(encoding='utf-8'))
    system = re.search(r'const SYSTEM := """(.*?)"""',(PROJECT/'scripts/voice/decision_pipeline.gd').read_text(encoding='utf-8'),re.S).group(1)
    people = json.loads((PROJECT/'data/people.json').read_text(encoding='utf-8'))
    results = []
    unavailable = set()
    for index,(name,person_index,line,history) in enumerate(CASES):
        me = copy.deepcopy(people[person_index])
        for field in ('node','model','voice'):me.pop(field)
        me.update(heard_events=[],reflections=[],pending_plans=[])
        if history:
            me['heard_events'].append({'id':'prior','kind':'speech_intent','speaker':'player','text':'你觉得自己应该获得食物吗？'})
            me['reflections'].append({'event_id':'prior','private_interpretation':'我已经吃饱，希望辛苦的人获得食物。',
                'public_reply':'我已经吃过了，现在不饿。石头今天搬了很多柴，应该把食物分给他。',
                'public_reply_status':'已向玩家播放完成；未投递给其他成员'})
        event = {'id':name,'kind':'speech_intent','speaker':'player','text':line}
        me['heard_events'].append(event)
        prompt = system+'\n严格输出裸 JSON，不要代码围栏，所有文字字段保持简短。requires_deep 仅表示需要进一步判断，本轮不会触发额外模型调用。\n'+json.dumps({'self':me,'current_event':event},ensure_ascii=False)
        for model in (models if index%2==0 else list(reversed(models))):
            if model in unavailable:continue
            response = complete(prompt,config|{'model':model})
            item = {'case':name,'input':line,'requested_model':model,'result':response}
            results.append(item)
            (ROOT/'runtime/model_benchmark.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps({'case':name,'requested_model':model,'ok':response['ok'],'model':response.get('model'),
                'elapsed_ms':response.get('elapsed_ms'),'first_text_ms':response.get('first_text_ms'),
                'text':response.get('text'),'error':response.get('error'),'diagnostic':response.get('diagnostic')},ensure_ascii=True),flush=True)
            if not response['ok'] and 'not supported' in response.get('diagnostic',''):
                unavailable.add(model)
    for model in models:
        times=[x['result']['elapsed_ms'] for x in results if x['requested_model']==model and x['result']['ok']]
        if times: print(json.dumps({'model':model,'samples':len(times),'median_ms':statistics.median(times),'min_ms':min(times),'max_ms':max(times)}))


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--models',nargs='+',default=['gpt-5.6-luna','gpt-5.3-codex-spark'])
    run(parser.parse_args().models)
