import json,subprocess,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from motion_review import _review
from luau_builder import failure_message


class FailureDiagnosisTests(unittest.TestCase):
    def check_failure(self, answer, *, faults=None, status='completed', exit_code=1):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir()
            (folder/'source.luau').write_text('return function() return {ok=false} end',encoding='utf-8')
            data={'passed':False,'faults':faults or [],'result':{
                'runtime':{'status':status,'returned':{'ok':False,'code':'recipient_not_observed'},
                           'trace':[{'operation':'perceive','result':{'ok':True,'near':{'landmarks':{}}}}]},
                'facts':[],'failures':['技能实际执行未完成']}}
            (output/'motion.json').write_text(json.dumps(data),encoding='utf-8')
            response={'ok':True,'text':json.dumps(answer),'model':'fixture'}
            with patch('motion_review.run_hidden',return_value=subprocess.CompletedProcess([],exit_code,'','')),patch('motion_review.complete',return_value=response) as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','给两人分食',time.monotonic()+60)
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
