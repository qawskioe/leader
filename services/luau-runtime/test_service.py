"""本机隔离服务协议回归，不使用麦克风、模型或TTS。"""
import json
from pathlib import Path
import queue
import subprocess
import threading
import time
import unittest

EXE=Path(__file__).resolve().parent/'runtime/build/leader-skill-service.exe'

class Client:
    def __init__(self):
        self.process=subprocess.Popen([str(EXE)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        self.messages=queue.Queue()
        threading.Thread(target=self.read,daemon=True).start()
        assert self.messages.get(timeout=5)['type']=='ready'
    def read(self):
        for line in self.process.stdout:
            self.messages.put(json.loads(line))
    def send(self,**value):
        self.process.stdin.write(json.dumps(value)+'\n');self.process.stdin.flush()
        return self.messages.get(timeout=5)
    def start(self,code,ident='test',capabilities=(),arguments=None):
        return self.send(op='start',id=ident,source='return function(args, context)\n'+code+'\nend',capabilities=list(capabilities),arguments=arguments or {},context={'self':'person_003'})
    def close(self):
        if self.process.poll() is None:
            self.process.stdin.write('{"op":"shutdown"}\n');self.process.stdin.flush()
            try:self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
        self.process.stdin.close();self.process.stdout.close();self.process.stderr.close()

class ServiceTests(unittest.TestCase):
    def setUp(self):self.client=Client();self.addCleanup(self.client.close)
    def test_nearby_carried_target_does_not_chase_its_own_rotation(self):
        source=(Path(__file__).resolve().parents[2]/'data/skills/go_to_known.luau').read_text(encoding='utf-8')
        r=self.client.send(op='start',id='near',source=source,capabilities=['recall_locations','walk_options','look_toward'],arguments={'object':'bag','distance':1.0},context={})
        operations=[]
        for _ in range(110):
            if r['type']!='world_request':break
            operation=r['request']['operation'];operations.append(operation)
            response={'ok':True}
            if operation=='walk_options':
                response={'observation_id':'frame','near':{'held_objects':[{'id':'bag','hand':'Hand.R'}]},'known':{'bag':{'position':{'x':0.33,'y':0.8,'z':0.24}}}}
            r=self.client.send(op='resume',id='near',sequence=r['sequence'],result=response)
        self.assertEqual(r['type'],'completed',r)
        self.assertTrue(r['result']['ok'],r)
        self.assertNotIn('look_toward',operations)

    def test_arithmetic_functions_and_loop(self):
        r=self.client.start('local function twice(x) return x*2 end\nlocal n=0\nfor i=1,10 do n+=twice(i) end\nreturn {n=n, person=context.self}')
        self.assertEqual(r['result'],{'n':110,'person':'person_003'})
    def test_world_yield_resume(self):
        r=self.client.start('local result=world.request("grab",{object=args.object})\nreturn {accepted=result.ok}',capabilities=['grab'],arguments={'object':'box'})
        self.assertEqual(r['request']['arguments'],{'object':'box'})
        self.assertEqual(self.client.send(op='resume',id='test',sequence=1,result={'ok':True})['result'],{'accepted':True})
    def test_no_system_interfaces(self):
        r=self.client.start('return {io=io==nil, execute=os.execute==nil, require=require==nil, load=loadstring==nil, debug=debug.getregistry==nil}')
        self.assertTrue(all(r['result'].values()))
    def test_capability_denied(self):
        self.assertEqual(self.client.start('return world.request("set_inventory",{count=99})')['type'],'failed')
    def test_cpu_budget_and_recovery(self):
        start=time.monotonic();r=self.client.start('while true do end')
        self.assertEqual(r['type'],'failed');self.assertIn('compute_budget',r['error'])
        self.assertLess(time.monotonic()-start,1)
        self.assertEqual(self.client.start('return {ok=true}')['type'],'completed')
    def test_memory_budget(self):
        r=self.client.start('local data=table.create(100000000)\nreturn {ok=true}')
        self.assertEqual(r['type'],'failed')
        self.assertEqual(self.client.start('return {ok=true}')['type'],'completed')
    def test_isolation_and_cancel(self):
        self.client.start('secret=10\nreturn world.request("wait",{})','a',['wait'])
        r=self.client.start('return {clean=secret==nil}','b')
        self.assertTrue(r['result']['clean'])
        self.assertTrue(self.client.send(op='cancel',id='a')['existed'])
        self.assertEqual(self.client.send(op='resume',id='a',sequence=1,result={})['type'],'failed')
    def test_stale_reply(self):
        self.client.start('return world.request("wait",{})',capabilities=['wait'])
        self.assertEqual(self.client.send(op='resume',id='test',sequence=5,result={})['type'],'failed')
    def test_cyclic_result(self):
        self.assertEqual(self.client.start('local a={} a.self=a return a')['type'],'failed')
    def test_yield_without_world_request(self):
        self.assertEqual(self.client.start('coroutine.yield()')['type'],'failed')

if __name__=='__main__':unittest.main()
