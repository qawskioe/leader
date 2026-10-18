"""官方Codex执行参数；复用登录，不读取或导出登录凭据。"""
import os,json,subprocess,csv,re
from pathlib import Path,PurePosixPath,PureWindowsPath
from development_backend import linux_path

CLEAN_ENV=('OPENAI_BASE_URL','OPENAI_API_BASE','OPENAI_API_KEY','CODEX_API_KEY','CODEX_ACCESS_TOKEN','CODEX_APP_TOOLS_PIPE_PATH','CODEX_PERMISSION_PROFILE','CODEX_THREAD_ID','CODEX_SESSION_ID','CODEX_SQLITE_HOME','CODEX_INTERNAL_ORIGINATOR_OVERRIDE')

def native_windows(executable):
    return PureWindowsPath(executable).is_absolute()

def environment():
    # 保留现有CODEX_HOME认证；只清除父任务路由与会话注入，不更改用户全局环境。
    return {k:v for k,v in os.environ.items() if k.upper() not in CLEAN_ENV}

def cli_path(path, executable):
    return str(path).replace('\\','/') if native_windows(executable) else linux_path(path)

def stop(process):
    if process.poll() is not None:return
    if os.name=='nt':
        subprocess.run(['taskkill.exe','/PID',str(process.pid),'/T','/F'],capture_output=True,timeout=10,creationflags=subprocess.CREATE_NO_WINDOW)
    else:process.terminate()
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:process.kill();process.wait()

def prepare_workspace(workspace):
    """沙箱子账号新建文件后，宿主仍须能读取验收；授权仅限本次隔离工程。"""
    if os.name!='nt':return
    identity=subprocess.run(['whoami.exe','/user','/fo','csv','/nh'],capture_output=True,text=True,timeout=10,creationflags=subprocess.CREATE_NO_WINDOW)
    if identity.returncode:raise ValueError('无法确认Codex宿主Windows身份')
    rows=list(csv.reader(identity.stdout.splitlines()))
    sid=rows[0][-1] if rows else ''
    if not re.fullmatch(r'S-1-5-[0-9-]+',sid):raise ValueError('Codex宿主Windows SID无效')
    result=subprocess.run(['icacls.exe',str(workspace.resolve()),'/grant','*'+sid+':(OI)(CI)M'],capture_output=True,timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:raise ValueError('无法设置本次Codex隔离工程的宿主读取权限')

def command(executable,workspace,model,seconds,extra=(),windows_sandbox='elevated'):
    windows=native_windows(executable)
    work=cli_path(workspace,executable)
    if windows:
        runtime=PureWindowsPath(executable).parent.as_posix()
    else:
        parts=PurePosixPath(executable).parts
        runtime=str(PurePosixPath(*parts[:parts.index('node_modules')]) if 'node_modules' in parts else PurePosixPath(executable).parent)
    rules={':minimal':'read',work:'write',work+'/reference':'read',work+'/.git':'read',work+'/.hooks':'read',str(runtime):'read'}
    # Windows原生沙箱要求:root可读；写入受工程边界限制，不宣称目录外不可读。
    # elevated使用专用低权限用户；unelevated是隔离较弱的官方回退模式，须明确选择。
    if windows:rules[':root']='read'
    else:rules['/usr']='read'
    profile='permissions.leader_skill.filesystem={'+','.join(json.dumps(k)+'='+json.dumps(v) for k,v in rules.items())+'}'
    args=[executable,
          'exec','--ignore-user-config','--ephemeral','--json','--cd',work,
          '--model',model,'-c','default_permissions="leader_skill"','-c',profile,'-c','permissions.leader_skill.network.enabled=false','-c','approval_policy="never"',
          '-c','model_provider="openai"','-c','forced_login_method="chatgpt"','-c','service_tier="default"',
          *(['-c','windows.sandbox='+json.dumps(windows_sandbox),'-c','shell_environment_policy.inherit="core"'] if windows else ['-c','shell_environment_policy.inherit="none"','-c','shell_environment_policy.set.PATH="/usr/bin:/bin"']),*extra,'-']
    if windows:return args
    args=['/usr/bin/timeout','--signal=TERM','--kill-after=5',str(max(1,int(seconds))),*args]
    # 明确移除可能将官方执行器改路由到兼容服务的环境变量。
    variables=CLEAN_ENV
    clean=['env',*[item for name in variables for item in ('-u',name)],*args]
    return ['wsl.exe','--exec',*clean] if os.name=='nt' else clean


def infrastructure_failure(event):
    """只认终端尚未启动的CLI事件；脚本退出、模型台词不能冒充环境故障。"""
    item=event.get('item',{})
    if (event.get('type')=='item.completed' and isinstance(item,dict)
            and item.get('type')=='command_execution' and item.get('status')=='failed'
            and item.get('exit_code')==-1 and isinstance(item.get('aggregated_output'),str)
            and item['aggregated_output'].startswith('Failed to create unified exec process:')):
        return {'ok':False,'error':'Codex执行环境无法启动终端，本次技能编写已停止',
                'failure_kind':'development_environment','retryable':False}
    return None

def failed_call(stdout, returncode, folder, stderr=''):
    """只读CLI的服务错误事件，不以模型台词或工具输出判定是否可重试。"""
    for line in stderr.splitlines():
        if not line.startswith('Error: turn/start: turn/start failed: Input exceeds the maximum length of '):continue
        try:detail=json.loads(line.split('data: ',1)[1])
        except (ValueError,IndexError):continue
        if (isinstance(detail,dict) and detail.get('input_error_code')=='input_too_large' and type(detail.get('max_chars')) is int
                and type(detail.get('actual_chars')) is int and 0<detail['max_chars']<detail['actual_chars']):
            return {'ok':False,'error':'Codex输入超过接口字符上限，未开始模型审查','failure_kind':'input_size',
                    'retryable':False,'max_chars':detail['max_chars'],'actual_chars':detail['actual_chars'],'evidence':str(folder)}
    message=''
    for line in stdout.splitlines():
        try:event=json.loads(line)
        except ValueError:continue
        if not isinstance(event,dict):continue
        if event.get('type')=='error':value=event.get('message')
        elif event.get('type')=='turn.failed':value=event.get('error',{}).get('message') if isinstance(event.get('error'),dict) else None
        else:continue
        if isinstance(value,str):message=value.lower()
    capacity=any(value in message for value in ('selected model is at capacity','server is overloaded','temporarily unavailable'))
    return {'ok':False,'error':'官方模型暂时满载' if capacity else '官方Codex调用未完成，退出码'+str(returncode),
            'retryable':capacity,'evidence':str(folder)}

def analysis_input(folder,instructions,prompt,evidence=None):
    """大资料留在同一隔离工程的只读文件，保留全文，由审查模型选择读取。"""
    if evidence is not None:
        if not isinstance(evidence,dict):raise ValueError('分析证据必须是JSON对象')
        from evidence_index import EvidenceIndex
        def export(path,value):
            file=folder/path;file.parent.mkdir(parents=True,exist_ok=True)
            file.write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        export('reference/analysis-evidence.json',evidence)
        export('reference/analysis-index.json',EvidenceIndex(export).pack(evidence))
        return (instructions+'\n'+prompt+
                '\n证据入口是只读JSON目录reference/analysis-index.json。按场景、操作类别和evidence_file读取，核对各场景的实际结果及入口/依赖源码。'
                'reference/analysis-evidence.json保留未改动的整份证据。允许读取和计算JSON数据，不执行受检项目代码、不修改参考资料。'
                '最终只返回请求要求的JSON。')
    content=instructions+'\n此任务只分析给出的文本/图像，不修改文件，不执行项目代码。最终只返回要求的JSON。\n'+prompt
    if len(content)<=250000:return content
    reference=folder/'reference';reference.mkdir()
    (reference/'analysis-request.txt').write_text(content,encoding='utf-8')
    return (instructions+'\n完整分析请求及全部证据在只读文件reference/analysis-request.txt。'
            '请用终端按需读取并核验各场景，不只根据本文或文件存在作判断。允许读取和计算JSON数据，'
            '不得修改参考资料、运行受检项目代码或读取工程之外的用户文件。最终只返回请求要求的JSON。')

def communicate_analysis(process,instructions,seconds,cancelled):
    import time
    deadline=time.monotonic()+seconds;input_value=instructions
    while True:
        if cancelled():
            stop(process);stdout,stderr=process.communicate();return stdout,stderr,'cancelled'
        remaining=deadline-time.monotonic()
        if remaining<=0:
            stop(process);stdout,stderr=process.communicate();return stdout,stderr,'timeout'
        try:
            stdout,stderr=process.communicate(input_value,timeout=min(.2,remaining))
            return stdout,stderr,'completed'
        except subprocess.TimeoutExpired:input_value=None

def completed_analysis_result(stdout,output):
    """只恢复本次CLI完整结束事件及与其逐字一致的结果，不把部分台词当完成。"""
    try:
        events=[json.loads(line) for line in stdout.splitlines() if line.strip()]
        if not events or any(not isinstance(event,dict) for event in events):return None
        types=[event.get('type') for event in events]
        if (types[-1]!='turn.completed' or types.count('thread.started')!=1 or
                types.count('turn.started')!=1 or types.count('turn.completed')!=1 or
                any(kind in ('error','turn.failed') for kind in types)):return None
        final=next((event['item'].get('text') for event in reversed(events)
                    if event.get('type')=='item.completed' and isinstance(event.get('item'),dict)
                    and event['item'].get('type')=='agent_message'),None)
        if not isinstance(final,str) or not final.strip():return None
        stored=output.read_text(encoding='utf-8')
        return stored if stored.rstrip('\r\n')==final.rstrip('\r\n') else None
    except (OSError,ValueError,UnicodeError):return None

def text(prompt,config,images=None):
    import tempfile,time
    marker=Path(config['cancellation_file']) if config.get('cancellation_file') else None
    cancelled=lambda:marker is not None and marker.exists()
    if cancelled():return {'ok':False,'error':'Codex分析已取消，未发起模型调用','retryable':False}
    root=Path(__file__).resolve().parent/'runtime/codex-calls';root.mkdir(exist_ok=True)
    folder=Path(tempfile.mkdtemp(prefix='call_',dir=root));output=folder/'result.txt'
    prepare_workspace(folder)
    extra=['--output-last-message',cli_path(output,config['executable']),'-c','model_reasoning_effort='+json.dumps(config.get('reasoning_effort','medium'))]
    for image in images or []:extra+=['--image',cli_path(image,config['executable'])]
    seconds=config.get('total_timeout_seconds',180);started=time.monotonic()
    instructions=analysis_input(folder,config.get('instructions','严格返回JSON。'),prompt,config.get('analysis_evidence'))
    process=subprocess.Popen(command(config['executable'],folder,config['model'],seconds,extra,config.get('windows_sandbox','elevated')),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',env=environment(),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    stdout,stderr,state=communicate_analysis(process,instructions,seconds+15,cancelled)
    result=subprocess.CompletedProcess(process.args,process.returncode,stdout,stderr)
    (folder/'events.jsonl').write_text(result.stdout,encoding='utf-8')
    (folder/'stderr.log').write_text(result.stderr,encoding='utf-8')
    if state=='cancelled' or cancelled():return {'ok':False,'error':'Codex分析已取消，本次进程已停止','retryable':False,'evidence':str(folder)}
    if state=='timeout':
        # communicate_analysis已回收本次子进程；清理未及时退出不能抹掉完整模型结果。
        # 没有结束事件、正文不符或取消仍失败，后续规划/语义合同也照常独立校验。
        recovered=completed_analysis_result(result.stdout,output)
        if recovered is None:return {'ok':False,'error':'Codex调用超时','retryable':False,'evidence':str(folder)}
        return {'ok':True,'text':recovered,'model':config['model'],'elapsed_ms':round((time.monotonic()-started)*1000),
                'transport':'official_codex_chatgpt','evidence':str(folder),'completion_state':'completed_result_recovered_after_timeout'}
    if result.returncode or not output.exists():return failed_call(result.stdout,result.returncode,folder,result.stderr)
    return {'ok':True,'text':output.read_text(encoding='utf-8'),'model':config['model'],'elapsed_ms':round((time.monotonic()-started)*1000),'transport':'official_codex_chatgpt','evidence':str(folder)}
