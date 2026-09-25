import tempfile,unittest,json
from pathlib import Path
from development_backend import read_selection,model_config
from codex_process import command,environment
from unittest.mock import patch

class CodexTests(unittest.TestCase):
    def test_native_windows_keeps_native_paths_and_restricted_permissions(self):
        exe='C:/App/Codex/codex.exe'
        args=command(exe,'D:/Leader/job/workspace','gpt-6-astra',60)
        self.assertEqual(args[0],exe)
        self.assertNotIn('wsl.exe',args)
        self.assertNotIn('/usr/bin/timeout',args)
        self.assertEqual(args[args.index('--cd')+1],'D:/Leader/job/workspace')
        self.assertIn('windows.sandbox="elevated"',args)
        profile=next(x for x in args if x.startswith('permissions.leader_skill.filesystem='))
        self.assertIn('"D:/Leader/job/workspace/reference"="read"',profile)
        self.assertIn('"D:/Leader/job/workspace/.git"="read"',profile)
        self.assertNotIn('/usr',profile)

    def test_native_environment_reuses_login_without_parent_session_injection(self):
        with patch.dict('os.environ',{'CODEX_HOME':'D:/existing-login','OPENAI_API_KEY':'fixture','CODEX_THREAD_ID':'parent'},clear=True):
            self.assertEqual(environment(),{'CODEX_HOME':'D:/existing-login'})

    def test_windows_local_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'services/skill-runtime/runtime/development_backend.json';p.parent.mkdir(parents=True)
            p.write_text(json.dumps({'backend':'codex','runtime':'local','executable':'C:/App/codex.exe'}))
            self.assertEqual(read_selection(root)['runtime'],'local')

    def test_codex_never_loads_reverse_proxy_provider(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            config=model_config(root,{'backend':'codex','executable':'/bin/codex','model':'gpt-6-astra'})
            self.assertEqual(config['protocol'],'codex_cli')
            self.assertNotIn('url',config);self.assertNotIn('key',config);self.assertNotIn('fallback',config)

    def test_official_auth_and_sandbox_are_explicit(self):
        args=command('/bin/codex','/tmp/work','gpt-6-astra',60)
        self.assertIn('forced_login_method="chatgpt"',args)
        self.assertIn('model_provider="openai"',args)
        self.assertIn('--ignore-user-config',args)
        self.assertIn('default_permissions="leader_skill"',args)
        self.assertIn('permissions.leader_skill.network.enabled=false',args)
        self.assertNotIn('--dangerously-bypass-approvals-and-sandbox',args)
        for env in ('OPENAI_BASE_URL','OPENAI_API_KEY','CODEX_API_KEY'):
            i=args.index(env);self.assertEqual(args[i-1],'-u')

    def test_codex_can_be_selected_without_opencode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'services/skill-runtime/runtime/development_backend.json';p.parent.mkdir(parents=True)
            p.write_text(json.dumps({'backend':'codex','runtime':'wsl','executable':'/bin/codex','model':'gpt-6-astra'}))
            self.assertEqual(read_selection(root)['backend'],'codex')

if __name__=='__main__':unittest.main()
