"""OpenCode隔离宿主：复用其工具，仅桥接模型认证和Godot验证。Linux/WSL。"""
import base64
import http.client
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import threading
import time
import urllib.request
import urllib.error

class Host:
    def __init__(self,workspace,binary,provider,verify):
        self.workspace=Path(workspace).resolve();self.binary=Path(binary).resolve()
        self.provider=provider;self.verify=verify;self.token=secrets.token_urlsafe(32)
        self.calls=[];self.process=None;self.log=None
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):self.send_error(405)
            def do_POST(self):
                if self.headers.get('Authorization')!='Bearer '+owner.token:self.send_error(401);return
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<=4000000:self.send_error(413);return
                body=self.rfile.read(size)
                if self.path=='/v1/responses' and owner.provider is not None:
                    request=urllib.request.Request(owner.provider['url'],data=body,headers={'Authorization':'Bearer '+owner.provider['key'],'Content-Type':'application/json','User-Agent':'Leader-OpenCode-Probe'})
                    started=time.monotonic();complete=False;last_event='';http_status=None;failure=''
                    try:
                        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request,timeout=120) as upstream:
                            http_status=upstream.status
                            self.send_response(upstream.status);self.send_header('Content-Type',upstream.headers.get('Content-Type','text/event-stream'));self.end_headers()
                            while data:=upstream.readline():
                                self.wfile.write(data);self.wfile.flush()
                                if data.startswith(b'data:'):
                                    payload=data[5:].strip()
                                    try:event=json.loads(payload)
                                    except ValueError:event={}
                                    last_event=event.get('type',last_event)
                                    if last_event in ('response.completed','response.failed','response.incomplete','error'):
                                        complete=last_event=='response.completed'
                                        self.wfile.write(b'\n');self.wfile.flush();break
                                if time.monotonic()-started>240:failure='total_timeout';break
                            if not complete and not failure:failure='incomplete_response'
                    except urllib.error.HTTPError as error:
                        http_status=error.code;failure='http_error';self.send_error(error.code)
                    except (OSError,TimeoutError,http.client.HTTPException):
                        failure='stream_transport_error'
                    finally:
                        if http_status==200 and not complete and last_event not in ('response.failed','response.incomplete','error'):
                            # 明确通知客户端流失败，不能让工具回合永远停留在未结束状态。
                            event={'type':'error','code':'upstream_stream_incomplete','message':'Model stream ended without response.completed','param':None,'sequence_number':0}
                            try:self.wfile.write(b'data: '+json.dumps(event).encode()+b'\n\n');self.wfile.flush()
                            except OSError:pass
                        self.close_connection=True
                        record={'elapsed_ms':round((time.monotonic()-started)*1000),'http_status':http_status,'completed':complete,'last_event':last_event,'failure':failure}
                        with (owner.workspace.parent/'model_transport.jsonl').open('a',encoding='utf-8') as log:log.write(json.dumps(record)+'\n')
                    return
                if self.path!='/mcp':self.send_error(404);return
                message=json.loads(body)
                if 'id' not in message:self.send_response(202);self.end_headers();return
                method=message.get('method');params=message.get('params',{})
                if method=='initialize':result={'protocolVersion':params.get('protocolVersion','2024-11-05'),'capabilities':{'tools':{}},'serverInfo':{'name':'leader-verifier','version':'1'}}
                elif method=='tools/list':result={'tools':[{'name':'verify_skill','description':'使用宿主Godot独立回放当前技能；不能用文字宣称成功。失败可继续改文件后重试。','inputSchema':{'type':'object','properties':{},'additionalProperties':False}}]}
                elif method=='tools/call' and params.get('name')=='verify_skill' and not params.get('arguments',{}):
                    try:verdict=owner.verify()
                    except Exception as error:verdict={'passed':False,'error':type(error).__name__+': '+str(error)[:300]}
                    owner.calls.append(verdict)
                    result={'content':[{'type':'text','text':json.dumps(verdict,ensure_ascii=False)}],'isError':False}
                elif method=='ping':result={}
                else:
                    self.respond({'jsonrpc':'2.0','id':message['id'],'error':{'code':-32601,'message':'Unknown method'}});return
                self.respond({'jsonrpc':'2.0','id':message['id'],'result':result})
            def respond(self,result):
                data=json.dumps(result,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.server.daemon_threads=True
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)

    def start(self):
        self.thread.start();port=self.server.server_port
        # OpenCode 1.18把--port 0当作默认4096；人物并发学习必须分配独立端口。
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1',0));execution_port=reserve.getsockname()[1]
        config={'$schema':'https://opencode.ai/config.json','share':'disabled','autoupdate':False,'enabled_providers':['leader'],
                'provider':{'leader':{'npm':'@ai-sdk/openai','name':'Leader configured model','options':{'baseURL':f'http://127.0.0.1:{port}/v1','apiKey':self.token},'models':{self.provider['model']:{'name':self.provider['model'],'limit':{'context':200000,'output':16000},'options':{'store':False}}}}},
                'mcp':{'world':{'type':'remote','url':f'http://127.0.0.1:{port}/mcp','oauth':False,'headers':{'Authorization':'Bearer '+self.token},'timeout':240000}},
                'permission':{'*':'allow','external_directory':'deny','webfetch':'deny','websearch':'deny'},'model':'leader/'+self.provider['model']}
        # 全新根文件系统；只有技能工程可写，reference挂为只读。凭据只在外部宿主内存。
        args=['bwrap','--unshare-pid','--die-with-parent','--new-session','--ro-bind','/usr','/usr','--symlink','usr/bin','/bin','--symlink','usr/lib','/lib','--symlink','usr/lib64','/lib64','--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/home/agent','--ro-bind','/etc/ssl/certs','/etc/ssl/certs','--ro-bind','/etc/resolv.conf','/etc/resolv.conf','--ro-bind',str(self.binary),'/opencode','--bind',str(self.workspace),'/workspace']
        if (self.workspace/'reference').exists():args+=['--ro-bind',str(self.workspace/'reference'),'/workspace/reference']
        for protected in ('.git','.hooks'):
            if (self.workspace/protected).exists():args+=['--ro-bind',str(self.workspace/protected),'/workspace/'+protected]
        args+=['--chdir','/workspace','--clearenv','--setenv','HOME','/home/agent','--setenv','PATH','/usr/bin:/bin','--setenv','LANG','C.UTF-8','--setenv','OPENCODE_CONFIG_CONTENT',json.dumps(config),'--setenv','OPENCODE_DISABLE_MODELS_FETCH','true','--setenv','OPENCODE_SERVER_PASSWORD',self.token,'/opencode','serve','--hostname','127.0.0.1','--port',str(execution_port)]
        self.log=open(self.workspace.parent/'opencode.log','w+',encoding='utf-8')
        self.process=subprocess.Popen(args,stdout=self.log,stderr=subprocess.STDOUT,start_new_session=True)
        deadline=time.monotonic()+40
        while time.monotonic()<deadline:
            self.log.flush();text=(self.workspace.parent/'opencode.log').read_text(encoding='utf-8')
            import re
            found=re.search(r'http://127\.0\.0\.1:(\d+)',text)
            if found:self.url=found.group(0);return self.request('GET','/global/health')
            if self.process.poll() is not None:raise RuntimeError('OpenCode未启动，检查本机opencode.log')
            time.sleep(.2)
        raise TimeoutError('OpenCode startup timeout')

    def request(self,method,path,data=None,timeout=10):
        request=urllib.request.Request(self.url+path,data=json.dumps(data).encode() if data is not None else None,method=method,headers={'Authorization':'Basic '+base64.b64encode(('opencode:'+self.token).encode()).decode(),'Content-Type':'application/json','x-opencode-directory':'/workspace'})
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request,timeout=timeout) as response:
            body=response.read();return json.loads(body) if body else None

    def close(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
        if self.thread.is_alive():self.server.shutdown()
        self.server.server_close()
        if self.log:self.log.close()
