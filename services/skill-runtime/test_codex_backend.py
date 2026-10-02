import tempfile,unittest,json,subprocess
from pathlib import Path
from development_backend import read_selection,model_config,resolve_codex_directory,CODEX_WINDOWS_COMPANIONS
from codex_process import command,environment,prepare_workspace
from unittest.mock import patch

class CodexTests(unittest.TestCase):
    def test_desktop_directory_survives_versioned_install_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);directory=root/'bin';directory.mkdir()
            old=directory/'old';old.mkdir();(old/'codex.exe').touch()
            new=directory/'new';new.mkdir();(new/'codex.exe').touch()
            prerelease=directory/'preview';prerelease.mkdir();(prerelease/'codex.exe').touch()
            for folder in [old,new,prerelease]:
                for name in CODEX_WINDOWS_COMPANIONS:(folder/name).touch()
            incomplete=directory/'incomplete';incomplete.mkdir();(incomplete/'codex.exe').touch()
            versions={'old':'0.158.0','new':'0.159.2','preview':'0.159.2-alpha.12'}
            def version(command,**kwargs):
                self.assertEqual(command[1:],['--version'])
                self.assertNotEqual(Path(command[0]).parent,incomplete,'仅含CLI的不完整安装不可用于开发工具')
                return subprocess.CompletedProcess(command,0,stdout='codex-cli '+versions[Path(command[0]).parent.name]+'\n')
            config=root/'services/skill-runtime/runtime/development_backend.json';config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'backend':'codex','runtime':'local','executable':str(directory)}))
            with patch('development_backend.subprocess.run',side_effect=version):
                self.assertEqual(read_selection(root)['executable'],str(new/'codex.exe'))
                (old/'codex.exe').unlink()
                self.assertEqual(read_selection(root)['executable'],str(new/'codex.exe'))
            self.assertEqual(json.loads(config.read_text())['executable'],str(directory),'持久配置保留稳定目录')

    def test_directory_does_not_accept_unknown_binary_or_mask_missing_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp);(directory/'codex.exe').touch()
            for name in CODEX_WINDOWS_COMPANIONS:(directory/name).touch()
            with patch('development_backend.subprocess.run',return_value=subprocess.CompletedProcess([],0,stdout='something else')):
                with self.assertRaisesRegex(ValueError,'没有工具组件完整'):resolve_codex_directory(directory)

    def test_workspace_acl_is_scoped_to_current_host_and_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            target=Path(tmp)
            replies=[subprocess.CompletedProcess([],0,stdout='"host","S-1-5-21-123-1001"'),
                     subprocess.CompletedProcess([],0)]
            with patch('codex_process.os.name','nt'),patch('codex_process.subprocess.CREATE_NO_WINDOW',0,create=True),patch('codex_process.subprocess.run',side_effect=replies) as run:
                prepare_workspace(target)
                self.assertEqual(run.call_args_list[1].args[0],
                                 ['icacls.exe',str(target.resolve()),'/grant','*S-1-5-21-123-1001:(OI)(CI)M'])

    def test_invalid_identity_cannot_grant_acl(self):
        with tempfile.TemporaryDirectory() as tmp:
            target=Path(tmp)
            with patch('codex_process.os.name','nt'),patch('codex_process.subprocess.CREATE_NO_WINDOW',0,create=True),patch('codex_process.subprocess.run',return_value=subprocess.CompletedProcess([],0,stdout='"host","not-a-sid"')) as run:
                with self.assertRaises(ValueError):prepare_workspace(target)
                self.assertEqual(run.call_count,1)

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
