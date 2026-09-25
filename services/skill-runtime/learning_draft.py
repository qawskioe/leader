"""同一人物、同一技能目标的失败草稿；仅供再次编写，不授予技能。"""
import json
from motion_review import repair_evidence


def failed_draft(folder, request):
    person=request.get('verification_snapshot',{}).get('person_id')
    if not person:return {}
    statuses=sorted(folder.parent.glob('job_*/status.json'),key=lambda p:p.stat().st_mtime,reverse=True)
    for status_file in statuses:
        previous=status_file.parent
        if previous==folder:continue
        try:
            if json.loads(status_file.read_text(encoding='utf-8')).get('state')!='failed':continue
            old=json.loads((previous/'build_request.json').read_text(encoding='utf-8'))
            if old.get('goal_id')!=request['goal_id'] or old.get('verification_snapshot',{}).get('person_id')!=person:continue
            definition=json.loads((previous/'candidate_definition.json').read_text(encoding='utf-8'))
            program=json.loads(definition['program_json'])
            packet={'job':previous.name,'source':program['source'],'parameters':definition['parameters'],
                    'dependencies':definition.get('dependencies',{}),
                    'meaning':'本人同一目标的失败草稿，尚未掌握；旧观察不是当前事实。依据本次原话修正，依赖必须从当前已掌握版本重新选择；不能直接发布此草稿。'}
            arguments=previous/'test_arguments.json'
            if arguments.exists():
                packet['candidate_output']={key:definition[key] for key in ('name','description','parameters','parameter_kinds','dependencies')}
                packet['candidate_output'].update(source=program['source'],capabilities=program['capabilities'],test_arguments=json.loads(arguments.read_text(encoding='utf-8')))
            # 超时也有review，但可能没有motion；不能把上一版动作错误配给最新源码。
            reviews=sorted(previous.glob('motion_*/review.json'),key=lambda p:p.stat().st_mtime,reverse=True)
            if reviews:
                packet['previous_review']=json.loads(reviews[0].read_text(encoding='utf-8'))
                motion=reviews[0].parent/'motion.json'
                if motion.exists():
                    data=json.loads(motion.read_text(encoding='utf-8'))
                    packet['previous_execution']=repair_evidence(data['result'])
            return packet
        except (OSError,ValueError,KeyError,TypeError):
            continue # 未完成或损坏的旧草稿不是有效学习材料。
    return {}
