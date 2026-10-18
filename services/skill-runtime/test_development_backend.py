import json,sys,tempfile,time,unittest,subprocess,errno
from pathlib import Path
from unittest.mock import patch,MagicMock
from development_backend import run,atomic,close_stdin

class FakeWorkspace:
    approved=None
    def digest(self):return 'version-a'

class BackendTests(unittest.TestCase):
    def test_inspection_feedback_does_not_stop_worker_or_approve_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);script=folder/'worker.py';workspace=FakeWorkspace();modes=[]
            script.write_text('''import json,sys
for sequence,mode in enumerate(('inspect','run'),1):
 print(json.dumps({'kind':'verify','mode':mode,'sequence':sequence}),flush=True)
 reply=json.loads(sys.stdin.readline())['value']
 if mode=='inspect':assert reply['owner']=='executor' and not reply['retryable']
 else:assert reply['passed']
print(json.dumps({'kind':'result','value':{'ok':True}}),flush=True)
''')
            def verify(mode):
                modes.append(mode)
                if mode=='inspect':return {'passed':False,'owner':'executor','retryable':False,'error':'fix declaration'}
                workspace.approved={'digest':'version-a','definition':{'id':'a'},'commit':'actual-run'}
                return {'passed':True}
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(workspace,{'model':'fixture'},time.monotonic()+5,verify,lambda _:None,lambda:False,folder,{'backend':'codex'})
            self.assertEqual(modes,['inspect','run']);self.assertTrue(result['ok'])
            self.assertEqual(result['commit'],'actual-run')

    def test_repairable_fixture_feedback_can_adjust_validation_and_reverify(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);script=folder/'worker.py';workspace=FakeWorkspace();calls=[]
            script.write_text('''import json,sys
for sequence in (1,2):
 print(json.dumps({'kind':'verify','mode':'run','sequence':sequence}),flush=True)
 reply=json.loads(sys.stdin.readline())['value']
 if sequence==1:assert reply['failure_kind']=='verification_setup' and reply['retryable']
 else:assert reply['passed']
print(json.dumps({'kind':'result','value':{'ok':True}}),flush=True)
''')
            def verify(mode):
                calls.append(1)
                if len(calls)==1:return {'passed':False,'owner':'uncertain','retryable':True,'failure_kind':'verification_setup'}
                workspace.approved={'digest':'version-a','definition':{'id':'a'},'commit':'adjusted-fixture'}
                return {'passed':True}
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(workspace,{'model':'fixture'},time.monotonic()+5,verify,lambda _:None,
                           lambda:False,folder,{'backend':'codex'})
            self.assertEqual(len(calls),2);self.assertTrue(result['ok'])
            self.assertEqual(result['commit'],'adjusted-fixture')

    def test_nonretryable_host_failure_stops_worker_instead_of_rewriting_skill(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);script=folder/'worker.py'
            script.write_text('''import json,sys
from pathlib import Path
print(json.dumps({'kind':'verify','mode':'run','sequence':1}),flush=True)
reply=json.loads(sys.stdin.readline())
assert reply['value']['owner']=='executor' and not reply['value']['retryable']
assert json.loads(sys.stdin.readline())['kind']=='cancel'
(Path(__file__).parent/'stopped').write_text('yes')
''')
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+5,
                           lambda mode:{'passed':False,'owner':'executor','retryable':False},lambda _:None,
                           lambda:False,folder,{'backend':'codex'})
            self.assertFalse(result['ok']);self.assertIn('停止技能编写',result['error'])
            self.assertTrue((folder/'stopped').exists())

    def test_terminal_pipe_close_does_not_replace_cancel_but_other_errors_remain(self):
        process=MagicMock();process.poll.return_value=0
        for number in (errno.EPIPE,errno.EINVAL):
            process.stdin.close.side_effect=OSError(number,'fixture pipe closed')
            close_stdin(process)
            process.poll.return_value=None
            with self.assertRaises(OSError):close_stdin(process)
            process.poll.return_value=0
        process.stdin.close.side_effect=OSError(errno.EIO,'fixture unexpected IO')
        with self.assertRaises(OSError):close_stdin(process)

    def test_cancel_during_verify_does_not_reply_to_exited_worker_or_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);script=folder/'worker.py';cancelled=False
            script.write_text("import json,time\nprint(json.dumps({'kind':'verify','mode':'run','sequence':1}),flush=True)\ntime.sleep(.3)")
            real=subprocess.Popen
            def verify(mode):
                nonlocal cancelled
                time.sleep(.5);cancelled=True;return {'passed':False}
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+5,verify,lambda _:None,lambda:cancelled,folder,{'backend':'codex'})
            self.assertFalse(result['ok']);self.assertIn('已取消',result['error'])

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
print(json.dumps({'kind':'verify','mode':'run','sequence':1}),flush=True)
r=json.loads(sys.stdin.readline())
assert r['sequence']==1 and r['value']['passed']
print(json.dumps({'kind':'result','value':{'ok':True}}),flush=True)
''',encoding='utf-8')
            real=subprocess.Popen
            def launch(command,**kwargs):
                self.assertEqual(command[1:3],['-X','utf8'])
                return real([sys.executable,'-X','utf8',str(script)],**kwargs)
            def verify(mode):
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
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+10,lambda mode:None,lambda _:None,lambda:False,f,{'backend':'opencode'})
            self.assertFalse(result['ok'])

    def test_cancel_stops_worker_without_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp);script=f/'worker.py'
            script.write_text("import sys,json\nfrom pathlib import Path\nf=Path(__file__).parent\nassert json.loads(sys.stdin.readline())['kind']=='cancel'\n(f/'stopped').write_text('yes')")
            real=subprocess.Popen
            with patch('development_backend.subprocess.Popen',side_effect=lambda *a,**k:real([sys.executable,str(script)],**k)):
                result=run(FakeWorkspace(),{'model':'fixture'},time.monotonic()+10,lambda mode:None,lambda _:None,lambda:True,f,{'backend':'opencode'})
            self.assertFalse(result['ok']);self.assertTrue((f/'stopped').exists())

if __name__=='__main__':unittest.main()
