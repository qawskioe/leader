import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from contextlib import nullcontext
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from motion_review import incomplete_review, _review
from hidden_review import run_hidden

class PartialReviewTests(unittest.TestCase):
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
        # 此用例验证进程/输出清理；Python不接受Godot专用--wid参数。
        with patch('hidden_review.hidden_parent',return_value=nullcontext([])):
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                run_hidden([sys.executable,'-u','-c',"import time;print('partial marker',flush=True);time.sleep(5)"],timeout=.5)
        self.assertIn('partial marker',caught.exception.output)

if __name__=='__main__':unittest.main()
