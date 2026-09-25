"""官方Codex执行参数；复用登录，不读取或导出登录凭据。"""
import os,json,subprocess
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

def command(executable,workspace,model,seconds,extra=()):
    windows=native_windows(executable)
    work=cli_path(workspace,executable)
    if windows:
        runtime=PureWindowsPath(executable).parent.as_posix()
    else:
        parts=PurePosixPath(executable).parts
        runtime=str(PurePosixPath(*parts[:parts.index('node_modules')]) if 'node_modules' in parts else PurePosixPath(executable).parent)
    rules={':minimal':'read',work:'write',work+'/reference':'read',work+'/.git':'read',work+'/.hooks':'read',str(runtime):'read'}
    # Windows原生沙箱要求:root可读；它隔离写入和命令联网，不宣称目录外不可读。
    if windows:rules[':root']='read'
    else:rules['/usr']='read'
    profile='permissions.leader_skill.filesystem={'+','.join(json.dumps(k)+'='+json.dumps(v) for k,v in rules.items())+'}'
    args=[executable,
          'exec','--ignore-user-config','--ephemeral','--json','--cd',work,
          '--model',model,'-c','default_permissions="leader_skill"','-c',profile,'-c','permissions.leader_skill.network.enabled=false','-c','approval_policy="never"',
          '-c','model_provider="openai"','-c','forced_login_method="chatgpt"',
          *(['-c','windows.sandbox="elevated"','-c','shell_environment_policy.inherit="core"'] if windows else ['-c','shell_environment_policy.inherit="none"','-c','shell_environment_policy.set.PATH="/usr/bin:/bin"']),*extra,'-']
    if windows:return args
    args=['/usr/bin/timeout','--signal=TERM','--kill-after=5',str(max(1,int(seconds))),*args]
    # 明确移除可能将官方执行器改路由到兼容服务的环境变量。
    variables=CLEAN_ENV
    clean=['env',*[item for name in variables for item in ('-u',name)],*args]
    return ['wsl.exe','--exec',*clean] if os.name=='nt' else clean


def text(prompt,config,images=None):
    import tempfile,time
    root=Path(__file__).resolve().parent/'runtime/codex-calls';root.mkdir(exist_ok=True)
    folder=Path(tempfile.mkdtemp(prefix='call_',dir=root));output=folder/'result.txt'
    extra=['--output-last-message',cli_path(output,config['executable']),'-c','model_reasoning_effort='+json.dumps(config.get('reasoning_effort','medium'))]
    for image in images or []:extra+=['--image',cli_path(image,config['executable'])]
    seconds=config.get('total_timeout_seconds',180);started=time.monotonic()
    instructions=config.get('instructions','严格返回JSON。')+'\n此任务只分析给出的文本/图像，不修改文件，不执行项目代码。最终只返回要求的JSON。\n'+prompt
    process=subprocess.Popen(command(config['executable'],folder,config['model'],seconds,extra),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',env=environment(),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    timed_out=False
    try:stdout,stderr=process.communicate(instructions,timeout=seconds+15)
    except subprocess.TimeoutExpired:
        timed_out=True;stop(process);stdout,stderr=process.communicate()
    result=subprocess.CompletedProcess(process.args,process.returncode,stdout,stderr)
    (folder/'events.jsonl').write_text(result.stdout,encoding='utf-8')
    (folder/'stderr.log').write_text(result.stderr,encoding='utf-8')
    if timed_out:return {'ok':False,'error':'Codex调用超时','retryable':False,'evidence':str(folder)}
    if result.returncode or not output.exists():return {'ok':False,'error':'官方Codex调用未完成，退出码'+str(result.returncode),'retryable':False,'evidence':str(folder)}
    return {'ok':True,'text':output.read_text(encoding='utf-8'),'model':config['model'],'elapsed_ms':round((time.monotonic()-started)*1000),'transport':'official_codex_chatgpt','evidence':str(folder)}
