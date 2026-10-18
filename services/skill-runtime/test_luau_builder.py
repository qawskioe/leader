import json
from pathlib import Path
import sys,tempfile,unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
import luau_builder as builder
import development_backend

class BuilderTests(unittest.TestCase):
    def test_status_publish_tolerates_transient_reader(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);path=folder/'status.json';path.write_text('{"state":"old"}')
            original=Path.replace;calls=[]
            def replace(source,target):
                calls.append(1)
                if len(calls)<3:
                    self.assertEqual(json.loads(path.read_text()),{'state':'old'})
                    raise PermissionError('transient reader')
                return original(source,target)
            with patch.object(Path,'replace',replace):builder.write(folder,{'state':'writing','message':'test'})
            self.assertEqual(json.loads(path.read_text())['state'],'writing')
            self.assertEqual(len(calls),3)

    def setUp(self):
        engine=patch.object(builder,'resolve_godot',return_value='fixture-godot');engine.start();self.addCleanup(engine.stop)
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.folder=self.root/'services/skill-runtime/runtime/jobs/job_test';self.folder.mkdir(parents=True)
        (self.root/'services/skill-runtime/runtime/builder_provider.json').write_text(json.dumps({'url':'fixture','key':'fixture','model':'fixture'}))
        (self.root/'services/skill-runtime/luau_sdk.md').write_text('test SDK')
        (self.root/'services/skill-runtime/runtime/development_backend.json').write_text(json.dumps({'backend':'opencode','runtime':'wsl','executable':'/fixture/opencode'}))
        self.source='return function(args) return world.request("release",{object=args.object}) end'
        self.value={'name':'放下','description':'放下物品','source':self.source,'parameters':{'object':'目标'},'parameter_kinds':{'object':'reference'},'capabilities':['release'],'dependencies':{},'test_arguments':{'object':'bag'}}
        self.request={'world_operations':['release'],'owned_skills':{},'goal_id':'release','character_context':{},'revision':{},'creation':{'player_event':{'text':'松手'},'goal':'松手'}}

    def execute(self,passed=True,cancel=False):
        def backend(workspace,config,deadline,verify,status,cancelled,folder,selection):
            (workspace.root/'source.luau').write_text(self.source,encoding='utf-8')
            (workspace.root/'skill.json').write_text(json.dumps({k:v for k,v in self.value.items() if k!='source'}),encoding='utf-8')
            self.verify_receipt=verify('run')
            return {'ok':True,**workspace.approved} if workspace.approved else {'ok':False,'error':'not approved'}
        def review(*_,**__):
            if cancel:(self.folder/'cancelled').touch()
            motion=self.folder/'motion_1';motion.mkdir(exist_ok=True)
            (motion/'replay_budget.json').write_text(json.dumps({'planned_invocations':7,'timeout_seconds':123,'scene_timeout_seconds':113,'semantic_reserve_seconds':195}))
            return {'passed':passed,'owner':'skill','issues':[] if passed else ['not released']}
        with patch.object(development_backend,'ensure_available'),patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes') as planner,patch.object(builder,'review',side_effect=review) as reviewer,patch.object(development_backend,'run',side_effect=backend):
            result=builder.execute(self.folder,self.request)
        return result,planner,reviewer

    def test_real_files_git_and_verified_package(self):
        result,planner,reviewer=self.execute()
        self.assertEqual(result,0);planner.assert_called_once();reviewer.assert_called_once()
        package=json.loads((self.folder/'package.json').read_text())
        self.assertEqual(json.loads(package['definition']['program_json'])['source'],self.source)
        self.assertEqual(len(package['receipt']['development_commit']),40)
        self.assertTrue((self.folder/'workspace/.git').is_dir())
        self.assertEqual(self.verify_receipt['replay_budget']['timeout_seconds'],123,"run应返回实际回放收据，不能在结束后重算")
        self.assertEqual((self.folder/'workspace/source.luau').read_text(),self.source)

    def test_inspection_reads_latest_workspace_plan_without_commit_or_attempt(self):
        from unittest.mock import patch
        self.request['verification_snapshot']={'person_id':'self','observations':{'self':{}}}
        preconditions={'baseline_participant_behaviors':[{'person':'player','behavior':'follow_actor'}],
                       'baseline_preconditions':{'origin':{'job':'job_approved'}},'baseline_adjustment':''}
        (self.folder/'verification_preconditions.json').write_text(json.dumps(preconditions),encoding='utf-8')
        def backend(workspace,config,deadline,verify,status,cancelled,folder,selection):
            proposal={k:v for k,v in self.value.items() if k!='source'}
            step={'conditions':[],'arguments':self.value['test_arguments']}
            proposal['verification_cases']=[{'name':'continued','steps':[step,step]}]
            (workspace.root/'source.luau').write_text(self.source,encoding='utf-8')
            (workspace.root/'skill.json').write_text(json.dumps(proposal),encoding='utf-8')
            (folder/'verification_cases.json').write_text(json.dumps([{'steps':[{}]*12}]))
            original_commit=workspace.git('rev-parse','HEAD');count=workspace.test_count
            first=verify('inspect')
            self.assertEqual(first['verification_preconditions'],preconditions)
            self.assertEqual(first['planned_invocations'],3);self.assertTrue(first['can_start'])
            self.assertEqual(first['remaining_tests'],builder.POLICY['attempts'])
            proposal['verification_cases']=[]
            (workspace.root/'skill.json').write_text(json.dumps(proposal),encoding='utf-8')
            with patch.object(builder.time,'monotonic',return_value=deadline-200):
                second=verify('inspect')
            self.assertEqual(second['planned_invocations'],1);self.assertFalse(second['can_start'])
            self.assertEqual(second['verification_preconditions'],preconditions)
            self.assertEqual(second['remaining_seconds'],200)
            self.assertEqual(workspace.git('rev-parse','HEAD'),original_commit)
            self.assertEqual(workspace.test_count,count);self.assertIsNone(workspace.approved)
            self.assertFalse((folder/'candidate_definition.json').exists())
            return {'ok':False,'error':'fixture inspect only'}
        with patch.object(development_backend,'ensure_available'),patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes'),patch.object(builder,'review') as replay,patch.object(development_backend,'run',side_effect=backend):
            self.assertEqual(builder.execute(self.folder,self.request),1)
        replay.assert_not_called()

    def test_verification_cases_bound_to_commit_but_not_world_permissions(self):
        self.request['verification_snapshot']={'person_id':'a','people':{'a':{}},'objects':{'bag':{'holder':'a'}},'containers':{'bag':[{}]},'observations':{'a':{}}}
        cases=[{'name':'empty','steps':[{'conditions':[{'kind':'consume_to_quantity','object':'bag','quantity':0}],'arguments':{'object':'bag'}}]}]
        self.value['verification_cases']=cases
        result,_,_=self.execute()
        self.assertEqual(result,0)
        self.assertEqual(json.loads((self.folder/'verification_cases.json').read_text()),cases)
        package=json.loads((self.folder/'package.json').read_text())
        self.assertNotIn('verification_cases',package['definition'])
        self.assertEqual(json.loads(package['definition']['program_json'])['capabilities'],['release'])
        commit=package['receipt']['development_commit']
        from skill_workspace import Workspace
        w=object.__new__(Workspace);w.root=self.folder/'workspace'
        self.assertEqual(json.loads(w.git('show',commit+':skill.json'))['verification_cases'],cases)

    def test_revision_continues_draft_but_keeps_accepted_review_baseline(self):
        original,_,_=builder.candidate(self.value,self.request)
        self.request['revision']={'ref':'release@old','definition':original,'player_event':{'text':'继续修订'}}
        draft_source='return function(args) return {ok=false,code="unfinished"} end'
        draft={'source':draft_source,'candidate_output':dict(self.value,source=draft_source)}
        def inspect(workspace,*args):
            self.assertEqual((workspace.root/'source.luau').read_text(),draft_source)
            self.assertEqual((self.folder/'previous_source.luau').read_text(),self.source)
            self.assertFalse((self.folder/'package.json').exists())
            return {'ok':False,'error':'fixture stopped before verification'}
        with patch.object(development_backend,'ensure_available'),patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes'),patch.object(builder,'failed_draft',return_value=draft),patch.object(development_backend,'run',side_effect=inspect):
            self.assertEqual(builder.execute(self.folder,self.request),1)
        self.assertFalse((self.folder/'package.json').exists())

    def test_failed_review_cannot_publish(self):
        result,_,_=self.execute(passed=False)
        self.assertEqual(result,1);self.assertFalse((self.folder/'package.json').exists())

    def test_existing_candidate_recheck_uses_full_policy_and_still_needs_approval(self):
        definition,_,_=builder.candidate(self.value,self.request)
        (self.folder/'build_request.json').write_text(json.dumps(self.request))
        (self.folder/'candidate_definition.json').write_text(json.dumps(definition))
        (self.folder/'source.luau').write_text(self.source)
        with patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes'),patch.object(builder.time,'monotonic',return_value=1000),patch.object(builder,'review',return_value={'passed':False,'owner':'skill','issues':['未批准']}) as reviewer:
            self.assertEqual(builder.verify_existing(self.folder),1)
        self.assertEqual(reviewer.call_args.kwargs['deadline'],1000+builder.POLICY['budget_seconds'])
        self.assertFalse((self.folder/'package.json').exists())

    def test_cancellation_during_review_cannot_publish(self):
        result,_,_=self.execute(cancel=True)
        self.assertEqual(result,1);self.assertFalse((self.folder/'package.json').exists())

    def test_plan_failure_prevents_tools(self):
        with patch.object(development_backend,'ensure_available'),patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes',side_effect=ValueError('bad plan')),patch.object(development_backend,'run') as model:
            self.assertEqual(builder.execute(self.folder,self.request),1)
        model.assert_not_called()

    def test_disabled_does_not_plan_or_start_backend(self):
        (self.root/'services/skill-runtime/runtime/development_backend.json').unlink()
        with patch.object(development_backend,'ensure_available'),patch.object(builder,'ROOT',self.root),patch.object(builder,'prepare_outcomes') as planner,patch.object(development_backend,'run') as backend:
            self.assertEqual(builder.execute(self.folder,self.request),1)
        planner.assert_not_called();backend.assert_not_called()
        self.assertIn('已关闭',(self.folder/'status.json').read_text(encoding='utf-8'))

    def test_missing_component_fails_before_cloud_planning(self):
        with patch.object(builder,'ROOT',self.root),patch.object(development_backend,'ensure_available',side_effect=ValueError('未安装OpenCode')),patch.object(builder,'prepare_outcomes') as planner:
            self.assertEqual(builder.execute(self.folder,self.request),1)
        planner.assert_not_called()
        self.assertIn('未安装OpenCode',(self.folder/'status.json').read_text(encoding='utf-8'))

    def test_new_skill_cannot_import_unowned_dependency(self):
        with self.assertRaises(ValueError):builder.candidate(dict(self.value,dependencies={'step':'unknown@v1'}),self.request)

    def test_revision_preserves_parameter_contract(self):
        self.request['revision']={'ref':'release@old','definition':{'parameters':{'other':'x'},'parameter_kinds':{'other':'reference'}}}
        with self.assertRaises(ValueError):builder.candidate(self.value,self.request)

    def test_world_permissions_validated(self):
        with self.assertRaises(ValueError):builder.candidate(dict(self.value,capabilities=['system']),self.request)

if __name__=='__main__':unittest.main()
