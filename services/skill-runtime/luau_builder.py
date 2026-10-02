"""修订已经掌握的Luau技能；由模拟器和独立视觉审查批准版本。"""
import hashlib
import json
import time
import sys
import re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from revision_evidence import collect
from motion_review import review
from world_outcomes import prepare as prepare_outcomes
from learning_draft import failed_draft
from review_report import write_report

ROOT=Path(__file__).resolve().parents[2]
POLICY=json.loads((ROOT/'data/skill_build_policy.json').read_text(encoding='utf-8'))
sys.path.insert(0,str(ROOT/'services'))
from godot_path import resolve_godot

def write(folder,value):
    from development_backend import atomic
    atomic(folder/'status.json',value)
    write_report(folder)

def failure_message(error, verdict):
    if not verdict.get('failure_kind'):return error
    notes=[item for item in verdict.get('issues',[]) if isinstance(item,str)]
    return error+'；最后一次回放的归因建议：'+'；'.join(notes[:2])[:600]

def candidate(output, request):
    keys={'name','description','source','parameters','parameter_kinds','capabilities','dependencies','test_arguments'}
    if not isinstance(output,dict) or set(output)!=keys:raise ValueError('输出字段必须完整且没有额外字段')
    if not all(isinstance(output[k],str) for k in ('name','description','source')):raise ValueError('正文必须是字符串')
    if not 1<=len(output['name'])<=80 or not 1<=len(output['description'])<=500 or not 1<=len(output['source'].encode())<=60000:raise ValueError('正文长度无效')
    params=output['parameters'];kinds=output['parameter_kinds'];deps=output['dependencies'];args=output['test_arguments']
    if not all(isinstance(v,dict) for v in (params,kinds,deps,args)) or len(params)>16 or set(kinds)!=set(params) or set(args)!=set(params):raise ValueError('参数合同不完整')
    for key,value in params.items():
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',key) or not isinstance(value,str) or len(value)>200 or kinds[key] not in ('reference','text','number','integer','boolean','hand'):raise ValueError('参数声明无效')
    ops=output['capabilities']
    if not isinstance(ops,list) or any(op not in request['world_operations'] for op in ops) or len(ops)!=len(set(ops)):raise ValueError('世界权限无效')
    if len(deps)>16 or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',a) or ref not in request['owned_skills'] for a,ref in deps.items()):raise ValueError('依赖必须是本人已掌握版本')
    revision=request.get('revision',{})
    old=revision.get('definition',{})
    if old and (params!=old['parameters'] or kinds!={k:old.get('parameter_kinds',{}).get(k,'reference') for k in params}):raise ValueError('修订不能改变参数合同')
    program={'format':'leader-luau-1','source':output['source'],'source_sha256':hashlib.sha256(output['source'].encode()).hexdigest(),'capabilities':ops}
    definition={'id':request['goal_id'],'name':output['name'],'description':output['description'],'parameters':params,'parameter_kinds':kinds,'dependencies':deps,'program_json':json.dumps(program,ensure_ascii=False,separators=(',',':'))}
    if old:definition.update(revision_of=revision['ref'],internal=old.get('internal',False))
    return definition,program,args

def execute(folder,request):
    from skill_workspace import Workspace
    from development_backend import run,read_selection,ensure_available,model_config
    try:selection=read_selection(ROOT)
    except (ValueError,OSError) as error:
        write(folder,{'state':'failed','message':'技能开发后端配置错误：'+str(error)});return 1
    if selection['backend']=='disabled':
        write(folder,{'state':'failed','message':'动态技能开发已关闭；已有技能仍可执行'});return 1
    try:
        ensure_available(selection)
        ENGINE=resolve_godot()
    except (ValueError,OSError,TimeoutError) as error:
        write(folder,{'state':'failed','message':str(error)});return 1
    deadline=time.monotonic()+POLICY['budget_seconds']
    revision=request.get('revision',{});old=revision.get('definition',{})
    config=model_config(ROOT,selection)
    evidence,_images=collect(revision,request['character_context'],folder.parent) if revision else ({'trigger_event':request['creation']['player_event'],'requested_goal':request['creation']['goal']},[])
    (folder/'revision_evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
    cancelled=lambda:(folder/'cancelled').exists()
    if cancelled():return 1
    write(folder,{'state':'testing','model':config['model'],'message':'正在独立确定本次技能的验收条件'})
    try:prepare_outcomes(folder,request,config)
    except (ValueError,KeyError,TypeError) as error:
        write(folder,{'state':'failed','message':'未能确定验收条件：'+str(error)});return 1
    if cancelled() or time.monotonic()>=deadline:return 1
    draft=failed_draft(folder,request)
    (folder/'previous_failed_draft.json').write_text(json.dumps(draft,ensure_ascii=False),encoding='utf-8')
    if old:
        program=json.loads(old['program_json'])
        baseline={key:old.get(key,{}) for key in ('name','description','parameters','parameter_kinds','dependencies')}
        baseline.update(source=program['source'],capabilities=program['capabilities'],test_arguments={})
    else:
        baseline=draft.get('candidate_output',{'name':'','description':'','parameters':{},'parameter_kinds':{},'capabilities':[],'dependencies':{},'test_arguments':{},'source':''}).copy()
    (folder/'previous_source.luau').write_text(baseline.get('source',''),encoding='utf-8')
    # 保留已掌握版本作为独立审查基准；只让编写工作区从同版本失败草稿继续。
    if old and draft.get('candidate_output'):
        baseline=draft['candidate_output'].copy()
    workspace=Workspace(folder,request,baseline,(ROOT/'services/skill-runtime/luau_sdk.md').read_text(encoding='utf-8'),evidence,draft)
    # 已有视觉证据以只读工程文件交接，不让执行器依赖上个后端的私有路径。
    if _images:
        directory=workspace.root/'reference/visual';directory.mkdir()
        paths=[]
        for index,image_path in enumerate(_images):
            target=directory/('frame_%02d'%index+image_path.suffix)
            target.write_bytes(image_path.read_bytes());paths.append(target.relative_to(workspace.root).as_posix())
        workspace.export('reference/visual/index.json',{'files':paths,'meaning':'本人旧技能的历史隔离回放，不是当前实时视野；按需要读取。'})
    last_verdict={}
    def verify():
        nonlocal last_verdict
        if cancelled():return {'ok':False,'error':'已取消'}
        if workspace.test_count>=POLICY['attempts']:return {'ok':False,'error':'本次独立验证次数已用尽'}
        if deadline-time.monotonic()<25:return {'ok':False,'error':'剩余预算不足，未开始验证'}
        proposal=workspace.output()
        definition,program,arguments=candidate(proposal,request)
        workspace.test_count+=1;attempt=workspace.test_count
        commit=workspace.checkpoint('独立验证第%d版'%attempt)
        digest=hashlib.sha256(json.dumps(proposal,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
        if workspace.digest()!=digest:raise ValueError('提交期间候选发生变化，请重试验证')
        if workspace.git('show',commit+':source.luau')!=program['source']:raise ValueError('Git提交与受检源码不一致')
        if json.loads(workspace.git('show',commit+':skill.json'))!={k:v for k,v in proposal.items() if k!='source'}:raise ValueError('Git提交与受检声明不一致')
        for name,value in [('candidate_definition.json',definition),('candidate.json',program),('test_arguments.json',arguments)]:
            (folder/name).write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
        (folder/'source.luau').write_text(program['source'],encoding='utf-8')
        write(folder,{'state':'testing','attempt':attempt,'model':config['model'],'message':'工具已提交当前Git版本，正在独立回放'})
        verdict=review(folder,config,ROOT,ENGINE,attempt,deadline=deadline,goal=json.dumps({'original':revision.get('player_event',request.get('creation',{}).get('player_event',{})),'goal':request.get('creation',{}).get('goal',revision.get('feedback',''))},ensure_ascii=False))
        if cancelled() or time.monotonic()>=deadline:verdict={'passed':False,'owner':'executor','issues':['已取消或超过整轮时限，未批准']}
        last_verdict=verdict
        workspace.export('feedback/review_%d.json'%attempt,workspace.evidence_index.pack(verdict,'review'))
        if verdict['passed'] and workspace.digest()==digest:
            workspace.approved={'digest':digest,'definition':definition,'commit':commit,'review':verdict}
        return {'ok':verdict['passed'],'passed':verdict['passed'],'commit':commit,'feedback_file':'feedback/review_%d.json'%attempt,'owner':verdict.get('owner'),'retryable':verdict.get('retryable',False),'failure_kind':verdict.get('failure_kind',''),'remaining_tests':POLICY['attempts']-attempt}
    result=run(workspace,config,deadline,verify,lambda value:write(folder,value),cancelled,folder,selection)
    if not result['ok']:
        write(folder,{'state':'failed','message':failure_message(result['error'],last_verdict),'review':last_verdict});return 1
    if cancelled() or time.monotonic()>=deadline or workspace.digest()!=result['digest']:
        write(folder,{'state':'failed','message':'发布前版本变化、取消或超时，未加载'});return 1
    raw=json.dumps(result['definition'],ensure_ascii=False,separators=(',',':'))
    receipt={'verifier':'leader-luau-tests-v1','passed':True,'definition_json':raw,'definition_sha256':hashlib.sha256(raw.encode()).hexdigest(),'development_commit':result['commit']}
    (folder/'package.json').write_text(json.dumps({'definition':result['definition'],'receipt':receipt},ensure_ascii=False),encoding='utf-8')
    write(folder,{'state':'ready','model':config['model'],'message':'工具开发与独立验证通过，等待加载该Git版本','review':result['review']})
    return 0

def verify_existing(folder):
    """宿主修正验证器后重验已生成版本；不把旧通过结果挪用到新代码。"""
    ENGINE=resolve_godot()
    request=json.loads((folder/'build_request.json').read_text(encoding='utf-8'))
    definition=json.loads((folder/'candidate_definition.json').read_text(encoding='utf-8'))
    program=json.loads(definition['program_json'])
    if (folder/'source.luau').read_text(encoding='utf-8')!=program['source']:raise ValueError('候选源码与定义不一致')
    from development_backend import read_selection,model_config
    config=model_config(ROOT,read_selection(ROOT));config.update(reasoning_effort='medium')
    revision=request.get('revision',{});creation=request.get('creation',{})
    goal=json.dumps({'original':revision.get('player_event',creation.get('player_event',{})),'goal':creation.get('goal',revision.get('feedback',''))},ensure_ascii=False)
    if (folder/'cancelled').exists():return 1
    prepare_outcomes(folder,request,config)
    attempt='recheck_'+str(int(time.time()))
    write(folder,{'state':'testing','model':config['model'],'message':'宿主修正后重新独立回放已有候选，未重新生成代码'})
    verdict=review(folder,config,ROOT,ENGINE,attempt,goal=goal)
    if (folder/'cancelled').exists():return 1
    if not verdict['passed']:
        write(folder,{'state':'failed','message':'重新验证未通过，未加载候选','review':verdict});return 1
    raw=json.dumps(definition,ensure_ascii=False,separators=(',',':'))
    receipt={'verifier':'leader-luau-tests-v1','passed':True,'definition_json':raw,'definition_sha256':hashlib.sha256(raw.encode()).hexdigest()}
    (folder/'package.json').write_text(json.dumps({'definition':definition,'receipt':receipt},ensure_ascii=False),encoding='utf-8')
    write(folder,{'state':'ready','model':config['model'],'message':'已有候选经新一轮独立验证通过，等待加载','review':verdict})
    return 0

if __name__=='__main__':
    job=sys.argv[1] if len(sys.argv)>1 else ''
    if not re.fullmatch(r'job_[A-Za-z0-9_]+',job): raise SystemExit(2)
    folder=ROOT/'services/skill-runtime/runtime/jobs'/job
    try:
        request=json.loads((folder/'build_request.json').read_text(encoding='utf-8'))
        raise SystemExit(verify_existing(folder) if '--verify-existing' in sys.argv else execute(folder,request))
    except Exception as error:
        import traceback
        (folder/'host_error.json').write_text(json.dumps({'type':type(error).__name__,'errno':getattr(error,'errno',None),'winerror':getattr(error,'winerror',None),'filename':getattr(error,'filename',None),'traceback':traceback.format_exc()},ensure_ascii=False),encoding='utf-8')
        write(folder,{'state':'failed','message':'Luau修订失败：'+type(error).__name__})
        raise SystemExit(1)
