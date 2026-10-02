"""管理本机文字模型网关；不操作现有远端 Sub2API。"""
import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / 'runtime'
PYTHON = ROOT / '.venv/Scripts/python.exe'
STATE = RUNTIME / 'process.json'
PORT = 18090

def initialize():
    RUNTIME.mkdir(exist_ok=True)
    if not (RUNTIME/'gateway-key.txt').exists():
        (RUNTIME/'gateway-key.txt').write_text(secrets.token_urlsafe(32),encoding='utf-8')

def process_info(pid):
    command = f"Get-CimInstance Win32_Process -Filter 'ProcessId={int(pid)}' | Select-Object ProcessId,CommandLine,CreationDate | ConvertTo-Json -Compress"
    result=subprocess.run(['powershell.exe','-NoProfile','-Command',command],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
    return json.loads(result.stdout) if result.stdout.strip() else None

def owned_process():
    if not STATE.exists(): return None
    state=json.loads(STATE.read_text(encoding='utf-8'))
    info=process_info(state['pid'])
    if info and info['CreationDate']==state['created'] and str(ROOT/'run.py').lower() in info['CommandLine'].lower():
        return info
    return None

def listening():
    with socket.socket() as sock:
        sock.settimeout(0.3)
        return sock.connect_ex(('127.0.0.1',PORT))==0

def health():
    key=(RUNTIME/'gateway-key.txt').read_text(encoding='utf-8').strip()
    request=urllib.request.Request(f'http://127.0.0.1:{PORT}/local/status',headers={'Authorization':'Bearer '+key})
    with urllib.request.urlopen(request,timeout=3) as response:
        return json.load(response)

def start():
    initialize()
    if owned_process():
        print(json.dumps({'running':True,'status':health()},ensure_ascii=False));return
    if listening(): raise SystemExit('Port 18090 is already in use by another process; left unchanged')
    with (RUNTIME/'stdout.log').open('ab') as out,(RUNTIME/'stderr.log').open('ab') as err:
        proc=subprocess.Popen([str(PYTHON),str(ROOT/'run.py')],cwd=ROOT,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW|subprocess.CREATE_NEW_PROCESS_GROUP)
    info=process_info(proc.pid)
    if not info: raise SystemExit('Gateway exited during startup; inspect runtime/stderr.log')
    STATE.write_text(json.dumps({'pid':proc.pid,'created':info['CreationDate']}),encoding='utf-8')
    for _ in range(40):
        try:
            status=health()
            print(json.dumps({'running':True,'status':status},ensure_ascii=False));return
        except (OSError,urllib.error.URLError): time.sleep(0.25)
    raise SystemExit('Gateway did not pass authenticated readiness check')

def stop():
    info=owned_process()
    if not info:
        print('No matching managed gateway process; no process stopped');return
    os.kill(info['ProcessId'],signal.SIGTERM)
    for _ in range(40):
        if not listening():
            STATE.unlink(missing_ok=True)
            print('Managed gateway stopped');return
        time.sleep(0.25)
    raise SystemExit('Gateway stop not confirmed; inspect process before retrying')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['start','stop','status'])
    action=parser.parse_args().action
    if action=='start':start()
    elif action=='stop':stop()
    else:print(json.dumps({'managed_process':bool(owned_process()),'listening':listening(),'status':health() if owned_process() else None},ensure_ascii=False))
