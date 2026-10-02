import json,sys,tempfile,time,unittest,subprocess
from pathlib import Path
from unittest.mock import patch
from development_backend import run,atomic

class FakeWorkspace:
    approved=None
    def digest(self):return 'version-a'

class BackendTests(unittest.TestCase):
    def test_atomic_publish_retries_transient_windows_reader_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'progress.json';path.write_text('{"old":true}')
            real=Path.replace;calls=[]
            def replace(source,target):
                calls.append(1)
                if len(calls)<3:
                    self.assertEqual(json.loads(path.read_text()),{'old':True})
                    raise PermissionError('reader lock')
                return real(source,target)
            with patch.object(Path,'replace',replace):atomic(path,{'new':True})
            self.assertEqual(json.loads(path.read_text()),{'new':True})
            self.assertEqual(len(calls),3)

    def test_verification_request_returns_to_host_and_only_host_can_approve(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);workspace=FakeWorkspace();script=folder/'worker.py'
            script.write_text('''import json,time
from pathlib import Path
f=Path(__file__).parent
import sys
print(json.dumps({'kind':'progress','value':{'message':'正在验证中文进度'}},ensure_ascii=False),flush=True)
print(json.dumps({'kind':'verify','sequence':1}),flush=True)
r=json.loads(sys.stdin.readline())
assert r['sequence']==1 and r['value']['passed']
print(json.dumps({'kind':'result','value':{'ok':True}}),flush=True)
''',encoding='utf-8')
            real=subprocess.Popen
            def launch(command,**kwargs):
                self.assertEqual(command[1:3],['-X','utf8'])
                return real([sys.executable,'-X','utf8',str(script)],**kwargs)
            def verify():
                workspace.approved={'digest':'version-a','definition':{'id':'a'},'commit':'host-verified'}
                return {'passed':True}
            progress=[]
            with patch('development_backend.subprocess.Popen',side_effect=launch):
                result=run(workspace,{'model':'fixture'},time.monotonic()+10,verify,progress.append,lambda:False,folder,{'backend':'codex','runtime':'local'})
            self.assertTrue(result['ok'],result);self.assertEqual(result['commit'],'host-verified')
            self.assertEqual(progress,[{'message':'正在验证中文进度'}])

    def test_backend_claim_without_host_approval_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp);script=f/'worker.py'
            script.write_text("import json\nprint(json.dumps({'kind':'result','value':{'ok':True}}),flush=True)")
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+10,lambda:None,lambda _:None,lambda:False,f,{'backend':'opencode'})
            self.assertFalse(result['ok'])

    def test_cancel_stops_worker_without_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp);script=f/'worker.py'
            script.write_text("import sys,json\nfrom pathlib import Path\nf=Path(__file__).parent\nassert json.loads(sys.stdin.readline())['kind']=='cancel'\n(f/'stopped').write_text('yes')")
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+10,lambda:None,lambda _:None,lambda:True,f,{'backend':'opencode'})
            self.assertFalse(result['ok']);self.assertTrue((f/'stopped').exists())

if __name__=='__main__':unittest.main()
