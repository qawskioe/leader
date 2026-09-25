"""独立窗口关键帧与骨骼数据审查；图片只发给后台模型，不进入聊天输出。"""
import copy
import difflib
import json
import subprocess
import time
from text_model import complete
from hidden_review import run_hidden
from world_outcomes import evaluate,REVIEW_STAGE
from review_frames import select_frames, select_samples

def execution_evidence(result):
    """工程审查只展开各类最后一次观察；本地 motion.json 仍保留完整轨迹。"""
    packet=copy.deepcopy(result)
    trace=packet.get('runtime',{}).get('trace',[])
    queries={'perceive','recall_locations','walk_options'}
    last={step['operation']:index for index,step in enumerate(trace) if step.get('operation') in queries}
    for index,step in enumerate(trace):
        op=step.get('operation')
        if op in queries and last[op]!=index:
            trace[index]={'operation':op,'arguments':step.get('arguments',{}),'result':{'ok':step.get('result',{}).get('ok')},
                          'evidence_note':'早期完整观察保存在本地motion.json；此处仅展开同类最后一次观察，不代表早期观察相同。'}
    return packet

def visual_evidence(result):
    """视觉验收保留实际动作，观察查询只展开当前可见物；不是修复时的地图调试包。"""
    packet=copy.deepcopy(result)
    for step in packet.get('runtime',{}).get('trace',[]):
        if step.get('operation') in ('perceive','walk_options','recall_locations'):
            data=step.get('result',{})
            step['result']={'ok':data.get('ok'),'observation_id':data.get('observation_id'),
                            'visible_landmarks':data.get('near',{}).get('landmarks',{}),
                            'held_objects':data.get('near',{}).get('held_objects',[]),
                            'needs':data.get('needs',{}),
                            'note':'完整地面采样和记忆查询保存在本地motion.json；此处仅保留可见物与自身状态。'}
    return packet

def repair_evidence(result):
    """作者只接收本人操作证据；宿主全局前后快照留给独立验收。"""
    packet=execution_evidence(result)
    return {key:packet[key] for key in ('runtime','failures','arguments','facts') if key in packet}

def revision_comparison(folder, source):
    """审查与编写使用同一宿主历史，不让作者自述代替修改前的执行证据。"""
    request=json.loads((folder/'build_request.json').read_text(encoding='utf-8'))
    previous=folder/'previous_failed_draft.json'
    draft=json.loads(previous.read_text(encoding='utf-8')) if previous.exists() else {}
    prior_source=draft.get('source')
    prior_execution=draft.get('previous_execution')
    prior_review=draft.get('previous_review')
    origin={'kind':'failed_draft','job':draft.get('job')}
    origin.update(person_id=request.get('verification_snapshot',{}).get('person_id'),goal_id=request.get('goal_id'),selected_by='host_same_person_same_goal_latest_failed_draft')
    if not prior_source and request.get('revision'):
        definition=request['revision']['definition']
        prior_source=json.loads(definition['program_json'])['source']
        origin={'kind':'owned_skill','ref':request['revision']['ref']}
        file=folder/'revision_evidence.json'
        if file.exists():
            evidence=json.loads(file.read_text(encoding='utf-8'))
            prior_execution=evidence.get('visual_evidence',{}).get('runtime_result')
            prior_review=evidence.get('visual_evidence',{}).get('reviews')
    if not prior_source:return {'available':False,'reason':'没有宿主保存的修改前源码，不能假设保留旧行为'}
    return {'available':True,'origin':origin,'previous_source':prior_source,
            'source_diff':'\n'.join(difflib.unified_diff(prior_source.splitlines(),source.splitlines(),fromfile='previous',tofile='candidate',lineterm='')),
            'previous_execution':visual_evidence(prior_execution) if prior_execution else None,
            'previous_review':prior_review,
            'meaning':'宿主保存的历史源码和执行记录，仅用于前后比较；不是本次执行，未提供旧画面不代表已完成旧动作视觉审查。当前动作仍按本次回放独立验收。'}

def review(folder, config, root, engine, attempt, script='test_luau_candidate.gd', source_file='source.luau', goal='饮水', deadline=None):
    output=folder/f'motion_{attempt}'
    output.mkdir(parents=True,exist_ok=True)
    verdict=_review(folder,config,root,engine,attempt,script,source_file,goal,deadline)
    (output/'review.json').write_text(json.dumps(verdict,ensure_ascii=False,indent=2),encoding='utf-8')
    return verdict


def _review(folder, config, root, engine, attempt, script, source_file, goal, deadline):
    deadline=time.monotonic()+360 if deadline is None else deadline
    if deadline-time.monotonic()<15:return {'passed':False,'owner':'executor','retryable':False,'issues':['预算不足以开始独立回放']}
    output=folder/f'motion_{attempt}'
    args=[engine,'--path',str(root),'--rendering-method','gl_compatibility','--resolution','800x600',
          '--position','-1600,-1000','--max-fps','30','--script','res://tools/'+script,
          '--','--outdoor-preview','--skill-job='+folder.name,'--motion-dir='+output.name]
    try:
        process=run_hidden(args,timeout=min(165,deadline-time.monotonic()-10))
    except subprocess.TimeoutExpired:
        return {'passed':False,'owner':'executor','issues':['独立视觉回放超时，未批准技能']}
    (folder/f'motion_{attempt}.log').write_text(process.stdout+process.stderr,encoding='utf-8')
    if (folder/'cancelled').exists():return {'passed':False,'owner':'executor','issues':['已取消，不再发起视觉模型请求']}
    if not (output/'motion.json').exists():return {'passed':False,'owner':'executor','issues':['未生成动作记录']}
    data=json.loads((output/'motion.json').read_text(encoding='utf-8'))
    if 'SCRIPT ERROR:' in process.stdout+process.stderr or 'ERROR:' in process.stderr:
        return {'passed':False,'owner':'executor','retryable':False,'issues':['独立场景报告脚本/引擎错误；不能仅按退出码批准']}
    if process.returncode or not data['passed']:
        return {'passed':False,'owner':'executor' if data['faults'] else 'skill','retryable':not data['faults'],'issues':data['faults'] or [repair_evidence(data['result'])]}
    # 条件来自编写之前的独立规划，候选源码和自选参数不能修改它。
    try:
        plan=json.loads((folder/'outcome_plan.json').read_text(encoding='utf-8'))
        outcomes=evaluate(plan,data['result']['before'],data['result']['after'])
    except (OSError,ValueError,KeyError,TypeError) as error:
        verdict={'passed':False,'owner':'executor','retryable':False,'issues':['世界结果验收证据无效：'+str(error)]}
        (output/'review.json').write_text(json.dumps(verdict,ensure_ascii=False,indent=2),encoding='utf-8')
        return verdict
    (output/'outcomes.json').write_text(json.dumps(outcomes,ensure_ascii=False,indent=2),encoding='utf-8')
    if not outcomes['passed']:
        verdict={'passed':False,'owner':'skill','retryable':True,'outcomes':outcomes,
                 'issues':['实际结果未达成：'+row['description']+'；测量结果='+str(row['measured']) for row in outcomes['checks'] if not row['passed']]}
        (output/'review.json').write_text(json.dumps(verdict,ensure_ascii=False,indent=2),encoding='utf-8')
        return verdict
    frames=data['all_frames']
    if not frames:return {'passed':False,'owner':'executor','issues':['没有图像，不能进行视觉验证']}
    frames=select_frames(frames)
    (output/'review_frames.json').write_text(json.dumps(frames,ensure_ascii=False,indent=2),encoding='utf-8')
    images=[output/frame['file'] for frame in frames]
    # 保留全量本地数据，发送关键帧时间与约每0.2秒的骨骼采样。
    evidence={'world_outcomes':outcomes,'frames':frames,'note':data['note'],'samples':select_samples(data['samples'],frames),'sample_precision_note':'骨骼坐标显示到0.0001米；完整逐帧数据保留在本地。实际操作结果和验收数值未舍入。','execution':visual_evidence(data['result'])}
    evidence['revision_comparison']=revision_comparison(folder,(folder/source_file).read_text(encoding='utf-8'))
    evidence['review_stage']=REVIEW_STAGE
    prompt='''当前职责以review_stage定义的加载前验收阶段为边界；严格区分能力批准与加载后的任务执行。独立验收人物技能是否满足该阶段的玩家要求，并审查实际动作。candidate返回ok不等于目标完成；必须核对宿主记录的执行前后状态、真实facts、trace和测试参数是否覆盖玩家要求。只观察没有动作、取了又放回却声称拿住、无实际变化却声称消耗等必须拒绝。目标不可从本次证据确认时拒绝并写明缺什么证据，不能假设成功。后附按时间排列的第三人称关键帧，每张左上角有时间和阶段。结合骨骼数据和源码检查：阶段间突然复位、明显穿体、膝腿反折、胸腰异常扭转、手没有到水源或嘴边却声称完成、动作极不连贯。不要因简化画质、没有手指或水被画成蓝球而拒绝；蓝圆片是水源接触参考。只根据证据判断，不假装看到了帧间未提供的内容。宿主在结束时使用1.2秒连续恢复待机，trace里的host_restore_idle及相应关键帧是该真实清理证据，不能误当作候选源码遗漏的瞬移；仍需检查画面是否连续。世界规则：consume_unit的手部接触点到解剖嘴点距离<=0.20米才结算；body_point(mouth)返回嘴前约0.11米的饮用目标，避免手穿入头部，reach_point报告的是到该饮用目标的距离，两种距离不同是预期。samples里的坐标是回放世界坐标；操作trace里的坐标是各自observation_id的人物局部坐标，不能直接相减。按该游戏世界的接触规则审查，不要求真实流体/手指仿真。运行时关节角为导入骨架局部欧拉角，不可直接等同人体解剖角。源码的角度是相对rest，二者不能直接比较。
另请检查照明是否过曝、过暗或导致轮廓难以辨认，只有图像确实足以判断才visibility_ok=true；图像质量不足不能批准动作。
只返回JSON：{"passed":布尔,"visibility_ok":布尔,"owner":"skill"或"executor"或"uncertain","issues":[{"time_ms":整数,"problem":"明确问题","suggestion":"修改建议"}]}。无明显问题才passed=true且issues=[]。怀疑执行器无视源码或帧间跳变时owner=executor；仅修改模型的姿态/时序可解决时owner=skill；无法确定时uncertain。不要要求模型编写未开放接口。
'''+json.dumps(evidence,ensure_ascii=False)+'\n本次验证目标：'+goal+'；只检查目标相关动作，拿取/释放不需要送到嘴边。\n源码：\n'+(folder/source_file).read_text(encoding='utf-8')
    remaining=deadline-time.monotonic()
    if remaining<10:return {'passed':False,'owner':'executor','retryable':False,'issues':['回放已结束，但剩余预算不足以完成独立视觉审查']}
    review_config=dict(config,total_timeout_seconds=min(180,int(remaining)),read_timeout_seconds=min(config.get('read_timeout_seconds',80),int(remaining)),instructions='检查提供的动作关键帧和数据，严格输出审查JSON。',reasoning_effort='medium')
    # 视觉审查不降级到仅文字的备用模型；临时服务故障只重试审查，不改源码。
    review_config.pop('fallback',None)
    for verification_try in range(1,3):
        remaining=deadline-time.monotonic()
        if remaining<10:return {'passed':False,'owner':'executor','retryable':False,'issues':['剩余预算不足以重试视觉审查，候选未批准']}
        review_config.update(total_timeout_seconds=min(180,int(remaining)),read_timeout_seconds=min(config.get('read_timeout_seconds',80),int(remaining)))
        result=complete(prompt,review_config,images=images)
        (output/f'visual_model_{verification_try}.json').write_text(json.dumps(result,ensure_ascii=False),encoding='utf-8')
        if result.get('ok') or not result.get('retryable',False):break
    if time.monotonic()>deadline:return {'passed':False,'owner':'executor','retryable':False,'issues':['独立审查超过本次学习总预算，未批准']}
    if not result.get('ok'):return {'passed':False,'owner':'executor','issues':[result.get('error','视觉模型调用失败')]}
    try:
        decision=json.loads(result['text'])
        if type(decision.get('passed')) is not bool or type(decision.get('visibility_ok')) is not bool or decision.get('owner') not in ('skill','executor','uncertain') or not isinstance(decision.get('issues'),list):raise ValueError()
        if decision['passed'] and not decision['visibility_ok']:raise ValueError()
        if decision['passed'] and decision['issues']:raise ValueError()
        if not decision['passed'] and not decision['issues']:raise ValueError()
    except (ValueError,TypeError):return {'passed':False,'owner':'executor','issues':['视觉审查返回无效，不批准技能']}
    decision['outcomes']=outcomes
    decision['model']=result.get('model')
    decision['frames']=len(images)
    # owner 是视觉模型的归因猜测，不是硬证据；有效视觉意见都先允许修订技能。
    decision['retryable']=not decision['passed'] and decision['visibility_ok']
    (output/'review.json').write_text(json.dumps(decision,ensure_ascii=False,indent=2),encoding='utf-8')
    return decision
