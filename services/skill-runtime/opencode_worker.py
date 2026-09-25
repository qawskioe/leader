"""OpenCode适配进程：使用现成会话/工具，将验证交回任务宿主。"""
import json,sys,time,threading
from pathlib import Path
from development_backend import atomic
from opencode_host import Host

PROMPT='''你扮演reference/context中的人物，为自己开发Luau技能。Godot是世界，不能修改世界规则或编造知识、材料、结果。玩家原话优先于摘要。
这是游戏管理的独立技能工程。用已有文件/搜索/补丁/终端工具读取reference/task.json、reference/sdk.md、source.luau、skill.json，再按需读取本人资料、已掌握固定依赖和上次失败反馈。不要把全部资料机械读入，也不要假设记忆是实时事实。
仅修改source.luau与skill.json。source返回function(args,context)；skill.json包含name、description、parameters、parameter_kinds、capabilities、dependencies、test_arguments，不含source。保持修订的参数合同；新技能可自行设计。声明能力和依赖必须在本人已知范围内。
Git用于检查差异；宿主为每个受检版本提交，.git只读。调用world_verify_skill做真实隔离回放，读取反馈后可继续修订。若问题属于宿主执行器且不能在技能层合理修正，报告问题，不能篡改验收或规避物理。最多三次验证。通过后结束，不再改动文件。你的最终回复不能代替验收。
工作区只含本人可知资料，世界快照、验收器和凭据不在此处。现有技能、失败记录与无损记忆引用都可按需读取。'''

_STOP=threading.Event()
_REPLIES={}
_CONDITION=threading.Condition()
_OUTPUT_LOCK=threading.Lock()
def emit(kind,**values):
    with _OUTPUT_LOCK:print(json.dumps(dict(kind=kind,**values),ensure_ascii=False),flush=True)
def receive():
    for line in sys.stdin:
        command=json.loads(line)
        if command['kind']=='cancel':_STOP.set()
        elif command['kind']=='verify_result':
            with _CONDITION:
                _REPLIES[command['sequence']]=command['value'];_CONDITION.notify_all()
    _STOP.set()


def execute(folder):
    request=json.loads((folder/'backend_request.json').read_text(encoding='utf-8'));selection=request['selection']
    binary=Path(selection['executable'])
    if not binary.is_file():raise ValueError('指定的OpenCode未安装；请配置路径，不会自动下载')
    deadline=time.monotonic()+request['budget_seconds']
    cancelled=lambda:_STOP.is_set() or (folder/'cancelled').exists()
    root=Path(__file__).resolve().parents[2]
    config=root/'services/skill-runtime/runtime/builder_provider.json'
    if not config.exists():config=root/'services/text-gateway/runtime/text_model.json'
    provider=json.loads(config.read_text(encoding='utf-8'));provider['model']=request['model']
    sequence=[0]
    def verify():
        sequence[0]+=1;number=sequence[0]
        emit('verify',sequence=number)
        while time.monotonic()<deadline and not cancelled():
            with _CONDITION:
                if number in _REPLIES:return _REPLIES.pop(number)
                _CONDITION.wait(.1)
        return {'ok':False,'error':'验证等待已取消或超时'}
    host=Host(folder/'workspace',binary,provider,verify)
    try:
        health=host.start()
        session=host.request('POST','/session',{'title':'人物技能开发 '+folder.name})
        atomic(folder/'backend_session.json',{'backend':'opencode','session_id':session['id'],'version':health['version']})
        host.request('POST','/session/'+session['id']+'/prompt_async',{'model':{'providerID':'leader','modelID':provider['model']},'parts':[{'type':'text','text':PROMPT}]})
        last_progress=None
        while time.monotonic()<deadline and not cancelled():
            messages=host.request('GET','/session/'+session['id']+'/message')
            atomic(folder/'opencode_messages.json',messages)
            assistant=[m for m in messages if m['info'].get('role')=='assistant']
            if assistant:
                last=assistant[-1];info=last['info'];parts=last.get('parts',[])
                tools=[p for p in parts if p.get('type')=='tool']
                detail=tools[-1]['tool'] if tools else '思考'
                progress={'state':'testing' if detail=='world_verify_skill' else 'writing','model':provider['model'],'message':'OpenCode：'+detail}
                if progress!=last_progress:emit('progress',value=progress);last_progress=progress
                if info.get('error'):return {'ok':False,'error':'OpenCode模型调用失败：'+str(info['error'])[:400]}
                if info.get('time',{}).get('completed') and info.get('finish') not in (None,'tool-calls'):
                    return {'ok':True,'message':'开发对话结束，批准由宿主判断'}
            time.sleep(.5)
        host.request('POST','/session/'+session['id']+'/abort',{})
        return {'ok':False,'error':'开发已取消或总预算用尽'}
    finally:host.close()

if __name__=='__main__':
    folder=Path(sys.argv[1]).resolve()
    threading.Thread(target=receive,daemon=True).start()
    try:result=execute(folder)
    except Exception as error:result={'ok':False,'error':type(error).__name__+': '+str(error)[:500]}
    atomic(folder/'backend_result.json',result)
    emit('result',value=result)
    raise SystemExit(0 if result.get('ok') else 1)
