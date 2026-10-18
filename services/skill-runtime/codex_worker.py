"""Codex后端适配：现有官方登录、原生工具及相同宿主验证接口。"""
import json,sys,time,subprocess,threading,queue
from pathlib import Path
from development_backend import atomic
from codex_process import command,environment,stop,prepare_workspace,infrastructure_failure
from opencode_host import Host
import opencode_worker as ipc

def progress_status(event,model):
    item=event.get('item',{})
    if not isinstance(item,dict) or not item.get('type'):return None
    # 只有真实宿主验证算验证阶段；列资源和其他MCP工具不代表技能已受检。
    arguments=item.get('arguments',{})
    if isinstance(arguments,str):
        try:arguments=json.loads(arguments)
        except ValueError:arguments={}
    testing=item.get('type')=='mcp_tool_call' and item.get('server')=='world' and item.get('tool')=='verify_skill' and isinstance(arguments,dict) and arguments.get('mode')=='run'
    return {'state':'testing' if testing else 'writing','model':model,
            'message':'正在独立验证技能' if testing else '正在编写和检查方法'}

def execute(folder):
    request=json.loads((folder/'backend_request.json').read_text(encoding='utf-8'));selection=request['selection']
    deadline=time.monotonic()+request['budget_seconds'];sequence=[0]
    cancelled=lambda:ipc._STOP.is_set() or (folder/'cancelled').exists()
    def verify(mode):
        sequence[0]+=1;number=sequence[0];ipc.emit('verify',sequence=number,mode=mode)
        while time.monotonic()<deadline and not cancelled():
            with ipc._CONDITION:
                if number in ipc._REPLIES:return ipc._REPLIES.pop(number)
                ipc._CONDITION.wait(.1)
        return {'ok':False,'error':'验证已取消或超时'}
    # 仅启动MCP验证端点；不启动OpenCode，也不转发任何模型请求。
    host=Host(folder/'workspace',selection['executable'],None,verify);host.thread.start()
    address='http://127.0.0.1:'+str(host.server.server_port)+'/mcp'
    extra=['-c','mcp_servers.world.url='+json.dumps(address),'-c','mcp_servers.world.http_headers={Authorization='+json.dumps('Bearer '+host.token)+'}',
           '-c','mcp_servers.world.enabled_tools=["verify_skill"]','-c','mcp_servers.world.tools.verify_skill.approval_mode="approve"','-c','mcp_servers.world.tool_timeout_sec='+str(request['budget_seconds']),'-c','model_reasoning_effort="high"']
    process=None;reader=None
    log=(folder/'codex_stderr.log').open('w',encoding='utf-8')
    try:
        prepare_workspace(folder/'workspace')
        args=command(selection['executable'],folder/'workspace',request['model'],request['budget_seconds'],extra,selection.get('windows_sandbox','elevated'))
        process=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,encoding='utf-8',env=environment(),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        process.stdin.write(ipc.PROMPT+'\n验证工具由world MCP提供。不要读取本技能工程之外的用户文件或凭据。\n');process.stdin.close()
        events=queue.Queue()
        def collect():
            for line in process.stdout:events.put(line)
        reader=threading.Thread(target=collect,daemon=True);reader.start()
        with (folder/'codex_events.jsonl').open('w',encoding='utf-8') as record:
            while True:
                if cancelled() or time.monotonic()>=deadline:return {'ok':False,'error':'Codex技能开发已取消或超时'}
                try:line=events.get(timeout=.1)
                except queue.Empty:
                    if process.poll() is not None and not reader.is_alive():break
                    continue
                record.write(line);record.flush()
                try:event=json.loads(line)
                except ValueError:continue
                if not isinstance(event,dict):continue
                if event.get('type')=='thread.started':atomic(folder/'backend_session.json',{'backend':'codex','session_id':event.get('thread_id')})
                failure=infrastructure_failure(event)
                if failure:return failure # finally只结束本次CLI，不触碰桌面或其他任务。
                progress=progress_status(event,request['model'])
                if progress:ipc.emit('progress',value=progress)
        return {'ok':process.returncode==0,'error':'Codex执行退出码'+str(process.returncode) if process.returncode else ''}
    finally:
        if process is not None:
            if process.poll() is None:
                stop(process)
            if reader is not None:reader.join(timeout=1)
            process.stdout.close()
        log.close();host.close()

if __name__=='__main__':
    folder=Path(sys.argv[1]).resolve();threading.Thread(target=ipc.receive,daemon=True).start()
    try:result=execute(folder)
    except Exception as error:result={'ok':False,'error':type(error).__name__+': '+str(error)[:500]}
    atomic(folder/'backend_result.json',result);ipc.emit('result',value=result)
    raise SystemExit(0 if result.get('ok') else 1)
