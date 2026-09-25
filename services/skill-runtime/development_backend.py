"""技能开发后端选择与任务交接；验收和发布仍属于游戏宿主。"""
import json,os,re,subprocess,sys,time,threading,queue
from pathlib import Path,PureWindowsPath


def read_selection(root):
    path=root/'services/skill-runtime/runtime/development_backend.json'
    value=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'backend':'disabled'}
    if not isinstance(value,dict) or value.get('backend') not in ('disabled','opencode','codex'):
        raise ValueError('未知技能开发后端；当前支持disabled、opencode、codex')
    if value['backend']!='disabled':
        if not {'backend','runtime','executable'}<=set(value) or set(value)-{'backend','runtime','executable','model'} or value['runtime'] not in ('local','wsl') or not isinstance(value['executable'],str) :
            raise ValueError('执行器需要runtime(local/wsl)与可执行文件绝对路径')
        windows=PureWindowsPath(value['executable']).is_absolute()
        if value['runtime']=='wsl' and not value['executable'].startswith('/'):
            raise ValueError('WSL执行器需要Linux绝对路径')
        if value['runtime']=='local' and not (windows or value['executable'].startswith('/')):
            raise ValueError('本机执行器需要绝对路径')
        if value['runtime']=='local' and windows and value['backend']!='codex':
            raise ValueError('Windows原生执行目前仅支持Codex')
    return value


def ensure_available(selection):
    if selection['backend']=='disabled':return
    if os.name=='nt' and selection['runtime']=='local':
        if not Path(selection['executable']).is_file():raise ValueError('本机Codex可执行文件不存在')
    elif os.name=='nt':
        for target in ([selection['executable'],'/usr/bin/bwrap'] if selection['backend']=='opencode' else [selection['executable']]):
            result=subprocess.run(['wsl.exe','--exec','test','-x',target],capture_output=True,timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            if result.returncode:raise ValueError('执行器或隔离运行组件未安装/不可执行：'+target)
    else:
        import shutil
        if not os.access(selection['executable'],os.X_OK) or (selection['backend']=='opencode' and not shutil.which('bwrap')):
            raise ValueError('OpenCode或bwrap未安装；请配置本机执行器，不会自动下载')


def model_config(root,selection):
    if selection['backend']=='codex':
        return {'protocol':'codex_cli','model':selection.get('model','gpt-6-astra'),'executable':selection['executable'],'reasoning_effort':'high','total_timeout_seconds':180}
    if selection['backend']=='disabled':raise ValueError('动态技能开发已关闭')
    path=root/'services/skill-runtime/runtime/builder_provider.json'
    if not path.exists():path=root/'services/text-gateway/runtime/text_model.json'
    config=json.loads(path.read_text(encoding='utf-8'))
    config.update(model=selection.get('model','gpt-6'),reasoning_effort='high',total_timeout_seconds=180)
    return config


def atomic(path,value):
    temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
    # Windows读取句柄短暂阻止WSL rename；保持旧完整文件，限定1秒重试。
    deadline=time.monotonic()+1.0
    while True:
        try:temporary.replace(path);return
        except PermissionError:
            if time.monotonic()>=deadline:raise
            time.sleep(.02)


def linux_path(path):
    value=str(path).replace('\\','/')
    if re.match(r'^[A-Za-z]:/',value):return '/mnt/'+value[0].lower()+value[2:]
    if value.startswith('/'):return value
    raise ValueError('无法转换WSL路径')


def run(workspace,config,deadline,verify,status,cancelled,folder,selection):
    if selection['backend']=='disabled':return {'ok':False,'error':'动态技能开发已关闭；已有技能仍可执行'}
    remaining=deadline-time.monotonic()
    if remaining<=0:return {'ok':False,'error':'技能开发总预算用尽'}
    atomic(folder/'backend_request.json',{'selection':selection,'budget_seconds':remaining,'model':config['model']})
    script=Path(__file__).with_name('codex_worker.py' if selection['backend']=='codex' else 'opencode_worker.py')
    command=(['wsl.exe','--exec','python3',linux_path(script),linux_path(folder)] if os.name=='nt' and selection.get('runtime')=='wsl' else [sys.executable,'-X','utf8',str(script),str(folder)])
    log=(folder/'backend_worker.log').open('w',encoding='utf-8')
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,encoding='utf-8',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    events=queue.Queue()
    def collect():
        try:
            for line in process.stdout:
                try:events.put(json.loads(line))
                except ValueError:events.put({'kind':'error','error':'后端通信不是有效JSON'})
        except (UnicodeError,OSError) as error:
            events.put({'kind':'error','error':'后端通信读取失败：'+type(error).__name__})
    reader=threading.Thread(target=collect,daemon=True);reader.start()
    result={'ok':False,'error':'开发后端退出但没有结果'}
    def send(value):
        process.stdin.write(json.dumps(value,ensure_ascii=False)+'\n');process.stdin.flush()
    try:
        while True:
            if cancelled() or time.monotonic()>=deadline:
                return {'ok':False,'error':'技能开发已取消或超时，未发布候选'}
            try:event=events.get(timeout=.1)
            except queue.Empty:
                if process.poll() is not None and not reader.is_alive():break
                continue
            kind=event.get('kind')
            if kind=='progress':status(event['value'])
            elif kind=='verify':
                try:value=verify()
                except (ValueError,KeyError,TypeError) as error:value={'ok':False,'error':str(error)}
                send({'kind':'verify_result','sequence':event['sequence'],'value':value})
            elif kind=='result':result=event['value']
            elif kind=='error':return {'ok':False,'error':event['error']}
            else:return {'ok':False,'error':'未知开发后端通信事件'}
        if not result.get('ok') or workspace.approved is None:return {'ok':False,'error':(result.get('error') or '开发结束但没有通过宿主验收')}
        if workspace.digest()!=workspace.approved['digest']:return {'ok':False,'error':'通过验收后文件发生变化，未发布'}
        return {'ok':True,**workspace.approved}
    finally:
        if process.poll() is None:
            try:send({'kind':'cancel'})
            except OSError:pass
            try:process.wait(timeout=20)
            except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        process.stdin.close();process.stdout.close();reader.join(timeout=1);log.close()
