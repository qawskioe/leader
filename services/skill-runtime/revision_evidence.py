"""修订证据只来自本人上下文及与旧技能源码匹配的验证任务。"""
import json
from pathlib import Path
from motion_review import repair_evidence


def collect(revision, context, jobs_root):
    ref=revision['ref']
    packet={
        'trigger_event':revision.get('player_event',{}),
        'trigger_meaning':'依据事件speaker/kind区分玩家教导与本人执行反馈；world/body事件不是玩家指令。',
        'daily_model_interpretation':revision.get('feedback',''),
        'interpretation_authority':'日常模型提出的方法问题，不是强制修法；依据原事件、本人目标与实际执行证据独立判断。',
        'heard_context':context.get('heard_events',[])[-8:],
        'execution_results':[r for r in context.get('execution_results',[]) if r.get('skill_ref')==ref][-4:],
        'interaction_rules':context.get('interaction_rules',{}),
        'visual_evidence':{'available':False,'reason':'没有历史画面；简化技能不要求图像，按世界事实和执行证据验证。'},
    }
    expected=json.loads(revision['definition']['program_json'])['source_sha256']
    matches=[]
    for candidate in Path(jobs_root).glob('job_*/candidate.json'):
        try:
            if json.loads(candidate.read_text(encoding='utf-8')).get('source_sha256')==expected:
                matches.append(candidate.parent)
        except (OSError,ValueError):
            continue  # 正在写入的任务不构成已发布证据。
    motions=[]
    for job in matches:
        motions.extend(job.glob('motion*/motion.json'))
    for path in sorted(motions,key=lambda p:p.stat().st_mtime,reverse=True):
        try:
            data=json.loads(path.read_text(encoding='utf-8'))
            frames=data.get('frames',[])
            if not frames: continue
            selected=[frames[round(i*(len(frames)-1)/7)] for i in range(8)] if len(frames)>8 else frames
            images=[]
            for frame in selected:
                image=(path.parent/frame['file']).resolve()
                if image.parent!=path.parent.resolve() or image.suffix.lower() not in ('.jpg','.png') or not image.is_file():
                    raise ValueError('无效关键帧路径')
                images.append(image)
            reviews={}
            for name in ('review.json','executor_visual_review.json'):
                p=path.parent/name
                if p.exists(): reviews[name]=json.loads(p.read_text(encoding='utf-8'))
            packet['visual_evidence']={'available':True,'job':path.parent.parent.name,'capture':path.parent.name,
                'source_sha256':expected,'frames':selected,'reviews':reviews,'runtime_result':repair_evidence(data.get('result',{})),
                'faults':data.get('faults',[]),'note':data.get('note',''),
                'provenance':'独立验证场景的历史关键帧，不是当前游戏实时视野；审查结论可能有误，需要结合图像判断。'}
            return packet,images
        except (OSError,ValueError,KeyError,TypeError):
            continue
    return packet,[]
