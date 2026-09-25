import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
import world_outcomes as outcomes
import motion_review
from review_frames import select_frames
from review_report import write_report


class OutcomeTests(unittest.TestCase):
    def setUp(self):
        self.before={'needs':{'thirst':80},'position':[0,0,0],
                     'objects':{'stone':{'position':[0,1,0],'holder':'actor','hand':'right'},
                                'basket':{'position':[4,0,0],'holder':'','hand':''}}}
        self.plan={'checks':[
            {'description':'放下石头','kind':'equals','path':['objects','stone','holder'],'expected':''},
            {'description':'放到篮子旁','kind':'near','path':['objects','stone','position'],
             'target_path':['objects','basket','position'],'radius':0.5}],
             'semantic_requirements':['核对动作自然且符合原话']}
        self.after=copy.deepcopy(self.before)
        self.after['objects']['stone'].update(holder='',hand='',position=[4.2,0,0])

    def test_planning_preserves_followup_request_but_identifies_preflight_stage(self):
        request={'verification_snapshot':{'person_id':'a','people':{'a':{'needs':{},'position':[0,0,0]}},'objects':{}},
                 'character_context':{},'creation':{'goal':'举袋','player_event':{'text':'先学会，之后演示给我看'}}}
        plan={'checks':[],'semantic_requirements':['真实抓握后举至胸前并停留']}
        with tempfile.TemporaryDirectory() as tmp,patch.object(outcomes,'complete',return_value={'ok':True,'text':json.dumps(plan)}) as model:
            outcomes.prepare(Path(tmp),request,{})
            payload=json.loads(model.call_args.args[0].split('\n')[-1])
            self.assertEqual(payload['original']['text'],'先学会，之后演示给我看')
            self.assertEqual(payload['review_stage']['name'],'candidate_preflight')
            self.assertIn('不能作为加载前的前置条件',payload['review_stage']['boundary'])

    def test_completed_code_without_world_change_fails(self):
        result=outcomes.evaluate(self.plan,self.before,self.before)
        self.assertFalse(result['passed'])
        self.assertEqual([x['passed'] for x in result['checks']],[False,False])

    def test_release_at_wrong_place_fails(self):
        self.after['objects']['stone']['position']=[0,0,0]
        result=outcomes.evaluate(self.plan,self.before,self.after)
        self.assertEqual([x['passed'] for x in result['checks']],[True,False])

    def test_move_near_without_release_fails(self):
        self.after['objects']['stone']['holder']='actor'
        self.assertFalse(outcomes.evaluate(self.plan,self.before,self.after)['passed'])

    def test_actual_world_result_passes(self):
        self.assertTrue(outcomes.evaluate(self.plan,self.before,self.after)['passed'])

    def test_cannot_move_reference_to_cheat_distance(self):
        self.after['objects']['stone']['position']=[0,0,0]
        self.after['objects']['basket']['position']=[0,0,0]
        self.assertFalse(outcomes.evaluate(self.plan,self.before,self.after)['passed'])

    def test_numeric_change_not_self_report(self):
        plan={'checks':[{'description':'降低口渴','kind':'delta_max','path':['needs','thirst'],'amount':-10}], 'semantic_requirements':[]}
        self.assertFalse(outcomes.evaluate(plan,self.before,self.after)['passed'])
        self.after['needs']['thirst']=60
        self.assertTrue(outcomes.evaluate(plan,self.before,self.after)['passed'])

    def test_missing_or_nonfinite_evidence_never_passes(self):
        for value in (None,[float('nan'),0,0],[0,0]):
            self.after['objects']['stone']['position']=value
            with self.assertRaises(ValueError):outcomes.evaluate(self.plan,self.before,self.after)
        del self.after['objects']['stone']
        with self.assertRaises(ValueError):outcomes.evaluate(self.plan,self.before,self.after)

    def test_unknown_fields_and_executable_conditions_rejected(self):
        for edit in ({'kind':'eval','source':'return true'}, {'radius':float('inf')}, {'target_path':['secret']}):
            plan=copy.deepcopy(self.plan);plan['checks'][1].update(edit)
            with self.assertRaises(ValueError):outcomes.validate(plan,self.before)

    def test_no_numeric_checks_still_requires_semantic_review(self):
        plan={'checks':[], 'semantic_requirements':['放得远一点是否符合情景']}
        self.assertEqual(outcomes.evaluate(plan,self.before,self.after)['checks'],[])
        with self.assertRaises(ValueError):outcomes.validate({'checks':[],'semantic_requirements':[]},self.before)

    def test_repair_evidence_keeps_last_observation_and_all_actions(self):
        source={'runtime':{'trace':[
            {'operation':'perceive','result':{'ok':True,'old':'old geometric details'}},
            {'operation':'grasp','result':{'ok':True}},
            {'operation':'perceive','result':{'ok':True,'latest':'latest geometric details'}},
            {'operation':'check_placement','result':{'ok':False,'code':'no_support'}}]}}
        packet=motion_review.execution_evidence(source)
        self.assertNotIn('old',packet['runtime']['trace'][0]['result'])
        self.assertEqual(packet['runtime']['trace'][2:],source['runtime']['trace'][2:])
        self.assertEqual(packet['runtime']['trace'][1],source['runtime']['trace'][1])
        self.assertIn('old',source['runtime']['trace'][0]['result'])

    def test_motion_selection_keeps_brief_core_actions_among_long_waits(self):
        frames=[{'file':str(i),'time_ms':i*200,'stage':'perceive / ok'} for i in range(200)]
        for i,stage in [(60,'grasp / ok'),(70,'reach_point / ok'),(75,'reach_point / ok'),(78,'release / ok')]:frames[i]['stage']=stage
        selected=select_frames(frames)
        ids={f['file'] for f in selected}
        self.assertEqual(len(selected),16)
        self.assertTrue({'0','199','60','70','75','78','81','84'}<=ids)
        self.assertEqual(selected,sorted(selected,key=lambda f:f['time_ms']))

    def test_repair_feedback_does_not_reveal_host_global_snapshot(self):
        source={'before':{'secret_object_position':[30,1,20]},'after':{'other_person_needs':50},
                'runtime':{'trace':[{'operation':'grasp','result':{'ok':False,'code':'not_in_contact'}}]},'failures':['执行失败']}
        packet=motion_review.repair_evidence(source)
        self.assertEqual(set(packet),{'runtime','failures'})
        self.assertEqual(packet['runtime'],source['runtime'])
        self.assertIn('before',source)

    def test_expired_deadline_does_not_launch_replay_or_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(motion_review,'run_hidden') as replay,patch.object(motion_review,'complete') as model:
                result=motion_review.review(Path(tmp),{},Path(tmp),'fixture',1,deadline=0)
            self.assertFalse(result['passed'])
            replay.assert_not_called();model.assert_not_called()

    def test_transient_visual_failure_retries_review_only(self):
        self._review(self.after,True,True,transient=True)

    def test_hard_visual_failure_is_preserved(self):
        self._review(self.after,False,True,hard_error=True)

    def test_report_explains_execution_error_and_keeps_details(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            issue={'failures':['技能实际执行未完成'],'runtime':{'returned':{'ok':False,'code':'no_support'}}}
            (folder/'status.json').write_text(json.dumps({'state':'failed','review':{'issues':[issue]}}))
            page=write_report(folder).read_text(encoding='utf-8')
            self.assertIn('技能实际执行未完成 · no_support',page)
            self.assertIn('展开程序执行证据',page)

    def test_review_blocks_false_success_before_visual_model(self):
        self._review(self.before,False,False)

    def test_review_continues_after_numeric_success(self):
        self._review(self.after,True,True)

    def test_semantic_rejection_still_blocks_numeric_success(self):
        self._review(self.after,False,True,visual_pass=False)

    def _review(self,after,passed,visual_called,visual_pass=True, transient=False, hard_error=False):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir()
            (folder/'build_request.json').write_text('{}')
            (folder/'outcome_plan.json').write_text(json.dumps(self.plan))
            (folder/'source.luau').write_text('return function() return {ok=true} end')
            data={'passed':True,'faults':[],'frames':[{'file':'frame.jpg','time_ms':1,'stage':'释放'}],'all_frames':[{'file':'frame.jpg','time_ms':1,'stage':'释放'}],'samples':[],'note':'fixture',
                  'result':{'before':self.before,'after':after,'runtime':{'returned':{'ok':True}}}}
            (output/'motion.json').write_text(json.dumps(data))
            decision={'passed':visual_pass,'visibility_ok':True,'owner':'skill','issues':[] if visual_pass else ['动作不符合要求']}
            responses=[{'ok':True,'text':json.dumps(decision)}]
            if transient:responses.insert(0,{'ok':False,'retryable':True,'error':'HTTP 503'})
            if hard_error:responses=[{'ok':False,'error':'HTTP 403'}]
            with patch.object(motion_review,'run_hidden',return_value=SimpleNamespace(stdout='',stderr='',returncode=0)),patch.object(motion_review,'complete',side_effect=responses) as model:
                result=motion_review.review(folder,{},folder,'fixture',1,goal='放到篮子旁')
            self.assertEqual(result['passed'],passed)
            self.assertEqual(model.called,visual_called)
            if visual_called:
                self.assertIn('candidate_preflight',model.call_args.args[0])
                self.assertIn('不能作为加载前的前置条件',model.call_args.args[0])
            if visual_called:self.assertEqual(model.call_count,2 if transient else 1)
            self.assertTrue((output/'review.json').exists())
            if hard_error:self.assertEqual(json.loads((output/'review.json').read_text())['issues'],['HTTP 403'])
            self.assertTrue((output/'outcomes.json').exists())
            (folder/'status.json').write_text(json.dumps({'state':'ready' if passed else 'failed','review':result}))
            page=write_report(folder).read_text(encoding='utf-8')
            self.assertIn('实际提交给审查模型的关键帧' if visual_called else '回放预览',page)

    def test_planner_only_receives_request_and_host_state(self):
        request={'verification_snapshot':{'person_id':'actor','people':{'actor':{'needs':self.before['needs'],'position':self.before['position']}},'objects':self.before['objects']},
                 'character_context':{},'creation':{'player_event':{'text':'放到篮子旁'},'goal':'放置'}}
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'source.luau').write_text('secret candidate cheating')
            with patch.object(outcomes,'complete',return_value={'ok':True,'text':json.dumps(self.plan)}) as model:
                outcomes.prepare(folder,request,{})
            self.assertNotIn('secret candidate cheating',model.call_args.args[0])
            self.assertIn('放到篮子旁',model.call_args.args[0])
            self.assertEqual(json.loads((folder/'outcome_plan.json').read_text()),self.plan)

if __name__=='__main__':unittest.main()
