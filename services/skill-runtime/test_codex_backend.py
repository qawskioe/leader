import tempfile,unittest,json,subprocess,io,sys,time
from pathlib import Path
from development_backend import read_selection,model_config,resolve_codex_directory,CODEX_WINDOWS_COMPANIONS
from codex_process import command,environment,prepare_workspace,failed_call,infrastructure_failure,analysis_input,communicate_analysis,completed_analysis_result,text
from unittest.mock import patch,MagicMock

class CodexTests(unittest.TestCase):
    def test_analysis_cancel_before_start_does_not_launch_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker=Path(tmp)/'cancelled';marker.touch()
            with patch('codex_process.subprocess.Popen') as start:
                result=text('analysis fixture',{'cancellation_file':str(marker),'model':'fixture','executable':'unused'})
            self.assertFalse(result['ok']);self.assertFalse(result['retryable']);start.assert_not_called()

    def test_analysis_cancel_inflight_stops_process_and_keeps_output(self):
        started=time.monotonic()
        with subprocess.Popen([getattr(sys,'_base_executable',sys.executable),'-u','-c',"import sys,time;sys.stdin.read();print('partial fixture',flush=True);time.sleep(30)"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) as process:
            stdout,stderr,state=communicate_analysis(process,'fixture input',5,lambda:time.monotonic()-started>.5)
            self.assertEqual(state,'cancelled');self.assertIsNotNone(process.poll())
            self.assertIn('partial fixture',stdout);self.assertLess(time.monotonic()-started,3)

    def test_analysis_poll_sends_input_once_and_preserves_completed_result(self):
        process=MagicMock();process.communicate.side_effect=[subprocess.TimeoutExpired([],1),('complete','')]
        stdout,stderr,state=communicate_analysis(process,'one input',1,lambda:False)
        self.assertEqual((stdout,stderr,state),('complete','','completed'))
        self.assertEqual(process.communicate.call_args_list[0].args,('one input',))
        self.assertEqual(process.communicate.call_args_list[1].args,(None,))

    def test_analysis_completed_turn_survives_process_cleanup_timeout(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);answer='{"checks":[],"semantic_requirements":["实际抵达"],"participant_behaviors":[]}'
            events=[{'type':'thread.started','thread_id':'fixture'},{'type':'turn.started'},
                    {'type':'item.completed','item':{'type':'agent_message','text':answer}},
                    {'type':'turn.completed','usage':{'input_tokens':10,'output_tokens':5}}]
            stdout='\n'.join(json.dumps(x,ensure_ascii=False) for x in events)+'\n'
            process=MagicMock();process.returncode=1
            def finish(*args):
                (folder/'result.txt').write_text(answer+'\n',encoding='utf-8')
                return stdout,'fixture cleanup diagnostic','timeout'
            with patch('tempfile.mkdtemp',return_value=str(folder)),patch('codex_process.prepare_workspace'),patch('codex_process.subprocess.Popen',return_value=process) as start,patch('codex_process.communicate_analysis',side_effect=finish):
                result=text('fixture',{'model':'fixture','executable':'C:/fixture/codex.exe'})
            self.assertTrue(result['ok'],'完成事件与本次结果一致时，CLI清理超时不得丢弃已完成生成')
            self.assertEqual(result['text'].strip(),answer)
            self.assertEqual(result['completion_state'],'completed_result_recovered_after_timeout')
            self.assertEqual(start.call_count,1)

    def test_timeout_cannot_promote_partial_failed_or_mismatched_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);answer='{"kind":"implementation"}'
            complete=[{'type':'thread.started'},{'type':'turn.started'},
                      {'type':'item.completed','item':{'type':'agent_message','text':answer}},
                      {'type':'turn.completed','usage':{'input_tokens':1,'output_tokens':1}}]
            for events,stored,state in [(complete[:-1],answer,'timeout'),
                                        (complete+[{'type':'turn.failed'}],answer,'timeout'),
                                        (complete,'different','timeout'),
                                        (complete,answer,'cancelled')]:
                with self.subTest(state=state,types=[x['type'] for x in events],matching=stored==answer):
                    def finish(*args):
                        (folder/'result.txt').write_text(stored,encoding='utf-8')
                        return '\n'.join(json.dumps(x) for x in events),'',state
                    process=MagicMock();process.returncode=1
                    with patch('tempfile.mkdtemp',return_value=str(folder)),patch('codex_process.prepare_workspace'),patch('codex_process.subprocess.Popen',return_value=process),patch('codex_process.communicate_analysis',side_effect=finish):
                        result=text('fixture',{'model':'fixture','executable':'C:/fixture/codex.exe'})
                    self.assertFalse(result['ok']);self.assertFalse(result['retryable'])

    def test_completed_hanging_child_is_reaped_and_its_exact_result_retained(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'result.txt';answer='{"checks":[],"semantic_requirements":["actual arrival"]}'
            events=[{'type':'thread.started'},{'type':'turn.started'},
                    {'type':'item.completed','item':{'type':'agent_message','text':answer}},
                    {'type':'turn.completed','usage':{'input_tokens':1,'output_tokens':1}}]
            script="import sys,time;from pathlib import Path;sys.stdin.read();Path(sys.argv[1]).write_text(%r,encoding='utf-8');print(%r,flush=True);time.sleep(30)"%(answer,'\n'.join(json.dumps(x) for x in events))
            started=time.monotonic()
            with subprocess.Popen([getattr(sys,'_base_executable',sys.executable),'-X','utf8','-u','-c',script,str(output)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)) as process:
                stdout,stderr,state=communicate_analysis(process,'fixture',1,lambda:False)
                self.assertEqual(state,'timeout');self.assertIsNotNone(process.poll())
                self.assertEqual(completed_analysis_result(stdout,output),answer)
                self.assertLess(time.monotonic()-started,4)

    def test_large_analysis_input_preserves_full_evidence_in_readonly_reference(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);large='观察记录'+('完整记录'*80000)
            sent=analysis_input(folder,'只做审查',large)
            self.assertLess(len(sent),1000)
            self.assertIn('reference/analysis-request.txt',sent)
            stored=(folder/'reference/analysis-request.txt').read_text(encoding='utf-8')
            self.assertTrue(stored.endswith(large));self.assertTrue(stored.startswith('只做审查'))
            self.assertIn('读取和计算JSON',sent)
            profile=next(x for x in command('C:/App/codex.exe','D:/job','fixture',60) if x.startswith('permissions.leader_skill.filesystem='))
            self.assertIn('"D:/job/reference"="read"',profile)

    def test_small_analysis_input_stays_inline_without_file_indirection(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);sent=analysis_input(folder,'只做审查','小资料')
            self.assertTrue(sent.endswith('小资料'));self.assertFalse((folder/'reference').exists())

    def test_indexed_analysis_preserves_all_cases_source_and_exact_facts(self):
        evidence={'execution':{'before':{'water':0},'after':{'water':2},
                    'runtime':{'trace':[{'operation':'take_unit','result':{'ok':True,'quantity':1,'source':'原水源'}} for _ in range(12)]},
                    'validation_cases':[{'name':'再次调用不重复交付','steps':[{'quantity':2,'position':[0.123456789,0.0,2]}]}]},
                  'code_scope':{'source':'完整源码'*80000},'revision_comparison':{'previous_execution':None}}
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);sent=analysis_input(folder,'独立审查','验证原水袋只交付两份',evidence)
            self.assertLess(len(sent),2000)
            self.assertIn('reference/analysis-index.json',sent)
            self.assertIn('验证原水袋只交付两份',sent)
            self.assertEqual(json.loads((folder/'reference/analysis-evidence.json').read_text(encoding='utf-8')),evidence)
            index=json.loads((folder/'reference/analysis-index.json').read_text(encoding='utf-8'))
            self.assertLess(len(json.dumps(index)),3000)
            files=list((folder/'reference/details').glob('*.json'))
            self.assertGreater(len(files),1)
            for file in files:json.loads(file.read_text(encoding='utf-8'))

    def test_local_turn_size_error_reports_numbers_without_leaking_stderr(self):
        detail={'input_error_code':'input_too_large','max_chars':1048576,'actual_chars':1257101}
        error='Error: turn/start: turn/start failed: Input exceeds the maximum length of 1048576 characters. (code -32602), data: '+json.dumps(detail)
        result=failed_call('',1,Path('fixture'),'unrelated private-value\n'+error)
        self.assertEqual(result['failure_kind'],'input_size');self.assertFalse(result['retryable'])
        self.assertEqual(result['actual_chars'],1257101);self.assertNotIn('private-value',result['error'])
        self.assertNotIn('failure_kind',failed_call(error,1,Path('fixture')),'模型/工具stdout不能冒充CLI的turn/start错误')

    def test_terminal_setup_failure_is_not_successful_skill_development(self):
        event={'type':'item.completed','item':{'type':'command_execution','status':'failed','exit_code':-1,
               'aggregated_output':'Failed to create unified exec process: helper_unknown_error: setup refresh had errors'}}
        result=infrastructure_failure(event)
        self.assertFalse(result['ok']);self.assertFalse(result['retryable'])
        self.assertEqual(result['failure_kind'],'development_environment')
        for field,value in [('type','agent_message'),('status','completed'),('exit_code',1)]:
            modified=json.loads(json.dumps(event));modified['item'][field]=value
            self.assertIsNone(infrastructure_failure(modified))
        event['type']='item.started';self.assertIsNone(infrastructure_failure(event))

    def test_only_host_verification_changes_learning_to_testing(self):
        from codex_worker import progress_status
        event={'item':{'type':'mcp_tool_call','server':'world','tool':'list_mcp_resources'}}
        self.assertEqual(progress_status(event,'fixture')['state'],'writing')
        event['item']['tool']='verify_skill'
        event['item']['arguments']={'mode':'inspect'}
        self.assertEqual(progress_status(event,'fixture')['state'],'writing')
        event['item']['arguments']={'mode':'run'}
        self.assertEqual(progress_status(event,'fixture')['state'],'testing')
        event['item']['server']='other'
        self.assertEqual(progress_status(event,'fixture')['state'],'writing')
        self.assertNotIn('mcp_tool_call',progress_status(event,'fixture')['message'])

    def test_worker_stops_own_cli_before_more_generation_after_setup_error(self):
        from codex_worker import execute
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'workspace').mkdir()
            (folder/'backend_request.json').write_text(json.dumps({'selection':{'executable':'/bin/codex'},'model':'fixture','budget_seconds':10}))
            event={'type':'item.completed','item':{'type':'command_execution','status':'failed','exit_code':-1,
                   'aggregated_output':'Failed to create unified exec process: helper_unknown_error: setup refresh had errors'}}
            process=MagicMock();process.stdin=io.StringIO();process.stdout=io.StringIO(json.dumps(event)+'\n')
            process.poll.return_value=None;process.returncode=0
            host=MagicMock();host.token='fixture-token';host.server.server_port=12345
            with patch('codex_worker.Host',return_value=host),patch('codex_worker.prepare_workspace'),patch('codex_worker.subprocess.Popen',return_value=process) as start,patch('codex_worker.ipc.emit') as emit,patch('codex_worker.stop') as stop:
                result=execute(folder)
            self.assertFalse(result['ok']);self.assertEqual(result['failure_kind'],'development_environment')
            stop.assert_called_once_with(process)
            self.assertIn('mcp_servers.world.tool_timeout_sec=10',start.call_args.args[0],"MCP等待共用整轮预算，不截断合法的长回放")
            self.assertFalse(any(call.args[0]=='verify' for call in emit.call_args_list))

    def test_capacity_service_failure_can_retry_same_review(self):
        events='\n'.join(json.dumps(x) for x in [
            {'type':'error','message':'Selected model is at capacity. Please try a different model.'},
            {'type':'turn.failed','error':{'message':'Selected model is at capacity. Please try a different model.'}}])
        result=failed_call(events,1,Path('fixture'))
        self.assertTrue(result['retryable']);self.assertIn('满载',result['error'])

    def test_model_text_and_tool_output_cannot_request_transport_retries(self):
        events=json.dumps({'type':'item.completed','item':{'type':'agent_message','text':'Selected model is at capacity.'}})
        self.assertFalse(failed_call(events,1,Path('fixture'))['retryable'])

    def test_last_service_error_wins_and_details_are_kept_local(self):
        events='\n'.join(json.dumps(x) for x in [
            {'type':'error','message':'Selected model is at capacity.'},
            {'type':'turn.failed','error':{'message':'Unauthorized credential private-value'}}])
        result=failed_call(events,1,Path('fixture'))
        self.assertFalse(result['retryable']);self.assertNotIn('private-value',result['error'])

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

    def test_game_workers_explicitly_disable_fast_on_both_platforms(self):
        for executable,workspace in [('C:/App/Codex/codex.exe','D:/Leader/job/workspace'),('/bin/codex','/tmp/work')]:
            args=command(executable,workspace,'fixture',60)
            tiers=[value for value in args if value.startswith('service_tier=')]
            self.assertEqual(tiers,['service_tier="default"'])
            self.assertEqual(args[args.index(tiers[0])-1],'-c')

    def test_explicit_windows_fallback_keeps_workspace_and_network_rules(self):
        args=command('C:/App/Codex/codex.exe','D:/Leader/job/workspace','gpt-6-astra',60,windows_sandbox='unelevated')
        self.assertIn('windows.sandbox="unelevated"',args)
        self.assertIn('permissions.leader_skill.network.enabled=false',args)
        profile=next(x for x in args if x.startswith('permissions.leader_skill.filesystem='))
        for path in ('reference','.git','.hooks'):self.assertIn('"D:/Leader/job/workspace/'+path+'"="read"',profile)
        self.assertNotIn('--dangerously-bypass-approvals-and-sandbox',args)

    def test_sandbox_mode_is_validated_and_shared_with_review_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'services/skill-runtime/runtime/development_backend.json';p.parent.mkdir(parents=True)
            value={'backend':'codex','runtime':'local','executable':'C:/App/codex.exe','windows_sandbox':'unelevated'}
            p.write_text(json.dumps(value));selection=read_selection(root)
            self.assertEqual(model_config(root,selection)['windows_sandbox'],'unelevated')
            for invalid in ('disabled','full-access',''):
                value['windows_sandbox']=invalid;p.write_text(json.dumps(value))
                with self.assertRaisesRegex(ValueError,'windows_sandbox'):read_selection(root)
            value.update(runtime='wsl',executable='/bin/codex',windows_sandbox='unelevated');p.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError,'windows_sandbox'):read_selection(root)

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
