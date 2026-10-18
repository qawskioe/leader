import json,subprocess,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from motion_review import _review
from luau_builder import failure_message,POLICY


class FailureDiagnosisTests(unittest.TestCase):
    def check_failure(self, answer, *, faults=None, status='completed', exit_code=1, missing_dependency=False):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir()
            (folder/'verification_preconditions.json').write_text(json.dumps({
                'baseline_participant_behaviors':[],
                'baseline_preconditions':{'origin':{'job':'job_approved'},'participant_behaviors':[{'person':'player','behavior':'follow_actor'}]},
                'baseline_adjustment':'本次改为停留，玩家不持续跟随。'}),encoding='utf-8')
            (folder/'source.luau').write_text('return function() return {ok=false} end',encoding='utf-8')
            (folder/'candidate_definition.json').write_text(json.dumps({'dependencies':{'go':'go@current'}}))
            owned={
                'go@current':{'id':'go','name':'当前寻路','parameters':{},'dependencies':{'find':'find@current'},
                              'program_json':json.dumps({'source':'-- CURRENT_ROUTE_SOURCE\nreturn function() end','capabilities':[]})},
                'find@current':{'id':'find','name':'查找','parameters':{},'dependencies':{},
                                'program_json':json.dumps({'source':'-- CURRENT_FIND_SOURCE\nreturn function() end','capabilities':[]})},
                'go@unused':{'program_json':json.dumps({'source':'UNUSED_SOURCE_OTHER_CONTEXT'})},
            }
            if missing_dependency:owned.pop('go@current')
            (folder/'build_request.json').write_text(json.dumps({'owned_skills':owned,'character_context':{'other_private':'PRIVATE_CONTEXT_NOT_CODE'}}))
            entry={'dependencies':{'go':'go@current'},'program_json':json.dumps({'source':'-- EXECUTED_ENTRY_SOURCE\nreturn function() end'})}
            (output/'code_scope.json').write_text(json.dumps({'entry':entry,'definitions':owned}))
            data={'passed':False,'faults':faults or [],'result':{
                'runtime':{'status':status,'returned':{'ok':False,'code':'recipient_not_observed'},
                           'trace':[{'operation':'perceive','result':{'ok':True,'near':{'landmarks':{}}}}]},
                'facts':[],'failures':['技能实际执行未完成']}}
            (output/'motion.json').write_text(json.dumps(data),encoding='utf-8')
            response={'ok':True,'text':json.dumps(answer),'model':'fixture'}
            with patch('motion_review.run_hidden',return_value=subprocess.CompletedProcess([],exit_code,'','')),patch('motion_review.complete',return_value=response) as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','给两人分食',time.monotonic()+POLICY['budget_seconds'])
            return verdict,model

    def test_safe_failure_gets_diagnosis_not_automatic_code_blame_or_approval(self):
        verdict,model=self.check_failure({'kind':'prerequisites','reason':'当前没有接收者位置线索','next_step':'先取得位置线索再验证'})
        self.assertEqual(model.call_count,1)
        self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])
        self.assertEqual(verdict['failure_kind'],'prerequisites')
        self.assertEqual(verdict['owner'],'uncertain')

    def test_fixable_logic_still_offers_repair(self):
        verdict,_=self.check_failure({'kind':'implementation','reason':'已有位置但技能没有读取','next_step':'读取已有观察后再调用移动'})
        self.assertFalse(verdict['passed']);self.assertTrue(verdict['retryable'])
        self.assertEqual(verdict['owner'],'skill')

    def test_diagnosis_receives_exact_reachable_dependency_sources(self):
        _,model=self.check_failure({'kind':'implementation','reason':'被调用方法没有检查其他方向','next_step':'重新观察可走方向'})
        prompt=model.call_args.args[0]
        self.assertIn('CURRENT_ROUTE_SOURCE',prompt)
        self.assertIn('CURRENT_FIND_SOURCE',prompt)
        self.assertIn('EXECUTED_ENTRY_SOURCE',prompt)
        self.assertNotIn('return function() return {ok=false} end',prompt)
        self.assertNotIn('UNUSED_SOURCE_OTHER_CONTEXT',prompt)
        self.assertNotIn('PRIVATE_CONTEXT_NOT_CODE',prompt)
        self.assertIn('本次改为停留',prompt)
        self.assertIn('job_approved',prompt)

    def test_missing_dependency_evidence_does_not_ask_model_to_guess(self):
        verdict,model=self.check_failure({},missing_dependency=True)
        model.assert_not_called()
        self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])
        self.assertEqual(verdict['owner'],'executor')
        self.assertIn('依赖源码证据不完整',verdict['issues'][0])

    def test_model_cannot_approve_a_failed_run(self):
        verdict,_=self.check_failure({'passed':True,'kind':'prerequisites','reason':'没找到','next_step':'直接批准'})
        self.assertFalse(verdict['passed']);self.assertEqual(verdict['failure_kind'],'unknown')

    def test_host_fault_never_gets_relabelled_by_model(self):
        verdict,model=self.check_failure({},faults=['执行器异常'])
        model.assert_not_called();self.assertEqual(verdict['owner'],'executor')
        self.assertFalse(verdict['passed'])

    def test_incomplete_runtime_is_not_a_normal_business_failure(self):
        verdict,model=self.check_failure({},status='failed')
        model.assert_not_called();self.assertFalse(verdict['passed'])

    def test_native_crash_is_not_a_business_failure(self):
        verdict,model=self.check_failure({},exit_code=3221225477)
        model.assert_not_called();self.assertEqual(verdict['owner'],'executor')
        self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])

    def test_character_feedback_keeps_diagnostic_not_raw_trace(self):
        message=failure_message('本次开发超时',{'failure_kind':'prerequisites','issues':['位置线索过时','下一步：重新取得位置',{'runtime':'private bulky trace'}]})
        self.assertIn('本次开发超时',message);self.assertIn('归因建议',message)
        self.assertIn('重新取得位置',message);self.assertNotIn('private bulky trace',message)
        self.assertEqual(failure_message('已取消',{}),'已取消')


if __name__=='__main__':unittest.main()
