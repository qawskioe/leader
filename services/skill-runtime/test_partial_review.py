import json
import os,time,ctypes
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from motion_review import incomplete_review, _review
from hidden_review import run_hidden,ReviewCancelled

def alive(pid):
    if os.name=='nt':
        from ctypes import wintypes
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
        kernel.GetExitCodeProcess.argtypes=[wintypes.HANDLE,ctypes.POINTER(wintypes.DWORD)]
        kernel.CloseHandle.argtypes=[wintypes.HANDLE]
        handle=kernel.OpenProcess(0x1000,False,pid)
        if not handle:return False
        try:
            code=wintypes.DWORD();return bool(kernel.GetExitCodeProcess(handle,ctypes.byref(code))) and code.value==259
        finally:kernel.CloseHandle(handle)
    try:return Path('/proc/%d/stat'%pid).read_text().rsplit(')',1)[1].split()[0] not in ('Z','X')
    except FileNotFoundError:return False

class PartialReviewTests(unittest.TestCase):
    def budget_guard_review(self, *, stderr='', stdout='', report=None, trace=True):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir()
            if trace:self.write_trace(output)
            (output/'replay_timeout.json').write_text(json.dumps(
                report if report is not None else {'schema':1,'budget_seconds':5,'elapsed_ms':5031,'shutdown':'drained'}),encoding='utf-8')
            # 超时报告不能被候选自报成功或未完整的motion记录覆盖。
            (output/'motion.json').write_text(json.dumps({'passed':True}),encoding='utf-8')
            budget={'planned_invocations':1,'timeout_seconds':15,'scene_timeout_seconds':5,'semantic_reserve_seconds':30}
            process=subprocess.CompletedProcess([],1,stdout,stderr)
            with patch('motion_review.replay_budget',return_value=budget),patch('motion_review.run_hidden',return_value=process),patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            model.assert_not_called()
            return verdict

    def test_scene_budget_guard_retains_progress_without_becoming_host_fault(self):
        verdict=self.budget_guard_review()
        self.assertFalse(verdict['passed']);self.assertEqual(verdict['owner'],'uncertain')
        self.assertTrue(verdict['retryable']);self.assertEqual(verdict['failure_kind'],'replay_budget')
        self.assertEqual(verdict['issues'][1]['runtime']['trace'][0]['result'],{'ok':True})
        self.assertEqual(verdict['replay_budget']['budget_seconds'],5)

    def test_budget_marker_does_not_hide_real_script_or_engine_failure(self):
        for stream,error in [('stdout','SCRIPT ERROR: Invalid access'),('stdout','ERROR: Rendering failed'),
                             ('stderr','ERROR: Invalid RID'),('stderr','ERROR: 3 resources still in use at exit (run with --verbose for details).')]:
            with self.subTest(stream=stream):
                verdict=self.budget_guard_review(**{stream:error})
                self.assertFalse(verdict['passed']);self.assertEqual(verdict['owner'],'executor')
                self.assertFalse(verdict['retryable'])

    def test_budget_report_contract_and_expected_limit_are_checked(self):
        for report in [[],{'schema':True,'budget_seconds':5,'elapsed_ms':5031,'shutdown':'drained'},
                       {'schema':1,'budget_seconds':10,'elapsed_ms':5031,'shutdown':'drained'},
                       {'schema':1,'budget_seconds':5,'elapsed_ms':-1,'shutdown':'drained'},
                       {'schema':1,'budget_seconds':5,'elapsed_ms':5031,'shutdown':'pending'}]:
            with self.subTest(report=report):
                verdict=self.budget_guard_review(report=report)
                self.assertFalse(verdict['passed']);self.assertEqual(verdict['owner'],'executor')
                self.assertFalse(verdict['retryable'])

    def test_budget_without_operation_evidence_cannot_be_approved_or_blindly_retried(self):
        verdict=self.budget_guard_review(trace=False)
        self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])
        self.assertEqual(verdict['owner'],'uncertain')

    def test_result_contract_errors_return_to_author_without_model_diagnosis(self):
        for code in ('result_size_exceeded','output_tables_require_string_keys','non_finite_number','string_too_large','non_data_result'):
            with self.subTest(code=code),tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);output=folder/'motion_1';output.mkdir();self.write_trace(output)
                failure={'validation_case':'baseline','step_index':0,'runtime':{'status':'error','code':code,'elapsed_ms':123}}
                (output/'runtime_error.json').write_text(json.dumps(failure),encoding='utf-8')
                process=subprocess.CompletedProcess([],1,'','ERROR: 隔离技能运行失败')
                with patch('motion_review.run_hidden',return_value=process),patch('motion_review.complete') as model:
                    verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
                self.assertEqual(verdict['failure_kind'],'result_contract')
                self.assertEqual(verdict['owner'],'skill');self.assertTrue(verdict['retryable'])
                self.assertEqual(verdict['issues'][1]['runtime_failure'],failure)
                self.assertFalse(verdict['passed']);model.assert_not_called()

    def test_runtime_failure_keeps_result_instead_of_becoming_a_generic_engine_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir();self.write_trace(output)
            failure={'validation_case':'continued','step_index':2,'runtime':{'status':'error','code':'fixture_specific_error','elapsed_ms':123}}
            (output/'runtime_error.json').write_text(json.dumps(failure),encoding='utf-8')
            process=subprocess.CompletedProcess([],1,'','ERROR: 隔离场景代码未正常结束')
            with patch('motion_review.run_hidden',return_value=process),patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            self.assertEqual(verdict['failure_kind'],'runtime')
            self.assertEqual(verdict['issues'][1]['runtime_failure'],failure)
            self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable']);model.assert_not_called()

    def test_unavailable_fixture_keeps_exact_condition_and_trigger_for_next_author(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir();self.write_trace(output)
            setup={'phase':'after_operation','operation':'approach','occurrence':1,
                   'error':'没有实际遮挡点','condition':{'kind':'participant_occluded','person':'player'},
                   'searched_distances_m':[1,2,3,4,5,6,7,8]}
            (output/'setup_error.json').write_text(json.dumps(setup),encoding='utf-8')
            process=subprocess.CompletedProcess([],1,'','ERROR: fixture failed')
            with patch('motion_review.run_hidden',return_value=process),patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            self.assertEqual(verdict['failure_kind'],'verification_setup')
            self.assertEqual(verdict['issues'][1]['verification_setup'],setup)
            self.assertFalse(verdict['passed']);self.assertTrue(verdict['retryable']);model.assert_not_called()
            self.assertIn('runtime',verdict['issues'][2])

    def test_engine_error_without_final_record_is_not_a_retryable_skill_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir();self.write_trace(output)
            process=subprocess.CompletedProcess([],1,'partial stdout','ERROR: fixture preparation failed\n')
            with patch('motion_review.run_hidden',return_value=process),patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            self.assertFalse(verdict['passed']);self.assertEqual(verdict['owner'],'executor')
            self.assertFalse(verdict['retryable']);model.assert_not_called()
            self.assertEqual(verdict['issues'][1]['runtime']['trace'][0]['result'],{'ok':True})
            self.assertIn('fixture preparation failed',(folder/'motion_1.log').read_text())

    def test_cancelled_before_review_spawns_nothing_and_calls_no_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'cancelled').touch()
            with patch('motion_review.run_hidden') as replay,patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])
            replay.assert_not_called();model.assert_not_called()
        with patch('hidden_review.subprocess.Popen') as start,patch('hidden_review._run_windows') as window:
            with self.assertRaises(ReviewCancelled):run_hidden(['unused'],cancelled=lambda:True)
            start.assert_not_called();window.assert_not_called()

    def test_cancel_during_replay_retains_output_without_semantic_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'motion_1').mkdir()
            error=ReviewCancelled();error.output='partial stdout';error.stderr='partial stderr'
            with patch('motion_review.run_hidden',side_effect=error),patch('motion_review.complete') as model:
                verdict=_review(folder,{},folder,'engine',1,'test.gd','source.luau','goal',None)
            self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable']);model.assert_not_called()
            self.assertEqual((folder/'motion_1.log').read_text(),'partial stdoutpartial stderr')

    def test_cancel_stops_owned_process_tree_and_preserves_another_process(self):
        python=getattr(sys,'_base_executable',sys.executable)
        with tempfile.TemporaryDirectory() as tmp:
            marker=Path(tmp)/'owned.json'
            code=("import subprocess,os,time,json\nfrom pathlib import Path\n"
                  "child=subprocess.Popen(["+repr(python)+",'-c','import time;time.sleep(30)'])\n"
                  "Path("+repr(str(marker))+").write_text(json.dumps([os.getpid(),child.pid]))\n"
                  "print('partial marker',flush=True)\ntime.sleep(30)")
            outsider=subprocess.Popen([python,'-c','import time;time.sleep(30)'])
            try:
                started=time.monotonic()
                with self.assertRaises(ReviewCancelled) as caught:
                    run_hidden([python,'-u','-c',code],timeout=5,cancelled=lambda:marker.exists() and time.monotonic()-started>.5)
                self.assertLess(time.monotonic()-started,3)
                self.assertIn('partial marker',caught.exception.output)
                for pid in json.loads(marker.read_text()):self.assertFalse(alive(pid),'取消后本任务进程仍存活')
                self.assertIsNone(outsider.poll(),'不能终止其他任务')
            finally:outsider.terminate();outsider.wait(timeout=5)

    def write_trace(self, path):
        rows=[{'type':'operation_started','request_id':1,'operation':'grasp','arguments':{'object':'basket/2'},'time_ms':10},
              {'type':'operation_finished','request_id':1,'step':{'operation':'grasp','arguments':{'object':'basket/2'},'result':{'ok':True}},'time_ms':20},
              {'type':'world_fact','fact':{'kind':'taken','person_id':'self','quantity':1},'time_ms':21},
              {'type':'operation_started','request_id':2,'operation':'reach_point','arguments':{'hand':'Hand.R'},'time_ms':30}]
        (path/'partial_trace.jsonl').write_text('\n'.join(json.dumps(r) for r in rows)+'\n{"type":',encoding='utf-8')

    def test_partial_steps_survive_truncated_last_line_without_becoming_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);self.write_trace(p)
            r=incomplete_review(p,'timeout')
            self.assertFalse(r['passed'])
            self.assertEqual(r['owner'],'uncertain');self.assertTrue(r['retryable'])
            evidence=r['issues'][1]
            self.assertEqual(evidence['runtime']['status'],'incomplete')
            self.assertEqual(evidence['runtime']['trace'][0]['result'],{'ok':True})
            self.assertEqual(evidence['runtime']['pending_operations'][0]['operation'],'reach_point')
            self.assertEqual(evidence['facts'][0]['quantity'],1)
            self.assertNotIn('returned',evidence['runtime'])

    def test_completed_calls_and_pending_call_survive_later_timeout_without_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);self.write_trace(p)
            rows=[{'type':'invocation_started','invocation_id':1,'step_index':0,'source_event_id':'original/call/0','root_request_id':'original','arguments':{'target':'person/person_002'},'time_ms':1},
                  {'type':'invocation_finished','invocation_id':1,'step_index':0,'source_event_id':'original/call/0','root_request_id':'original','arguments':{'target':'person/person_002'},'result':{'status':'completed','code':'returned','elapsed_ms':20,'returned':{'ok':True},'trace':['do not copy'],'context':{'private':True},'before':{'global':True},'after':{'global':True}},'time_ms':22},
                  {'type':'invocation_finished','invocation_id':2,'validation_case':'cancel_resume','step_index':1,'source_event_id':'changed/call/1','root_request_id':'changed','arguments':{'target':'water_source'},'result':{'status':'cancelled','code':'cancelled','elapsed_ms':4,'returned':{'ok':False,'code':'waiting'}},'time_ms':27},
                  {'type':'invocation_started','invocation_id':3,'validation_case':'cancel_resume','step_index':2,'source_event_id':'changed/call/2','root_request_id':'changed','arguments':{'target':'water_source'},'time_ms':30}]
            with (p/'partial_trace.jsonl').open('a',encoding='utf-8') as log:
                log.write('\n'+ '\n'.join(json.dumps(row) for row in rows)+'\n{"type":')
            verdict=incomplete_review(p,'timeout');runtime=verdict['issues'][1]['runtime']
            self.assertFalse(verdict['passed']);self.assertEqual(runtime['status'],'incomplete')
            self.assertEqual(len(runtime['invocations']),2)
            self.assertEqual(runtime['invocations'][0]['result'],{'status':'completed','code':'returned','elapsed_ms':20,'returned':{'ok':True}})
            self.assertEqual(runtime['invocations'][1]['result']['status'],'cancelled')
            self.assertEqual(runtime['invocations'][1]['validation_case'],'cancel_resume')
            self.assertEqual(runtime['pending_invocations'][0]['step_index'],2)
            self.assertEqual(runtime['pending_invocations'][0]['root_request_id'],'changed')
            self.assertNotIn('returned',runtime)

    def test_call_without_world_evidence_never_authorizes_retry_or_approval(self):
        for event_type in ['invocation_started','invocation_finished']:
            with self.subTest(event_type=event_type),tempfile.TemporaryDirectory() as tmp:
                p=Path(tmp)
                event={'type':event_type,'invocation_id':1,'step_index':0,'arguments':{},'result':{'status':'completed','returned':{'ok':True}},'time_ms':1}
                (p/'partial_trace.jsonl').write_text(json.dumps(event)+'\n',encoding='utf-8')
                verdict=incomplete_review(p,'timeout')
                self.assertFalse(verdict['passed']);self.assertFalse(verdict['retryable'])
                self.assertEqual(verdict['issues'][1]['runtime']['status'],'incomplete')

    def test_timeout_boundary_preserves_log_and_never_calls_visual_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);output=p/'motion_1';output.mkdir();self.write_trace(output)
            failure=subprocess.TimeoutExpired(['engine'],1,output='partial stdout',stderr='partial stderr')
            with patch('motion_review.run_hidden',side_effect=failure),patch('motion_review.complete') as model:
                r=_review(p,{},p,'engine',1,'test.gd','source.luau','goal',None)
            self.assertFalse(r['passed']);self.assertEqual(len(r['issues']),2)
            self.assertEqual((p/'motion_1.log').read_text(),'partial stdoutpartial stderr')
            model.assert_not_called()

    def test_absent_evidence_stays_failed(self):
        with tempfile.TemporaryDirectory() as tmp:
            r=incomplete_review(Path(tmp),'timeout')
            self.assertFalse(r['passed']);self.assertEqual(r['issues'],['timeout'])
            self.assertEqual(r['owner'],'uncertain');self.assertFalse(r['retryable'])

    def test_process_timeout_retains_actual_stdout(self):
        # 此用例验证进程/输出清理，并保留超时前实际写出的内容。
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            run_hidden([sys.executable,'-u','-c',"import time;print('partial marker',flush=True);time.sleep(5)"],timeout=.5)
        self.assertIn('partial marker',caught.exception.output)

if __name__=='__main__':unittest.main()
