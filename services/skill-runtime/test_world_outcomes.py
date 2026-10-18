import copy
import hashlib
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
from review_report import write_report


class BaselinePreconditionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.folder=Path(self.temp.name)/'job_revision';self.folder.mkdir()
        self.old=self.folder.parent/'job_approved';self.old.mkdir()
        self.definition={'id':'escort','name':'带路','parameters':{},'program_json':json.dumps({'source_sha256':'same_source'})}
        self.request={'revision':{'ref':'escort@approved','definition':self.definition,'feedback':'改进绕路','player_event':{'text':'保持带我过去，修好绕行'}},
                      'character_context':{'id':'a'},'verification_snapshot':{'person_id':'a','people':{'a':{'needs':{},'position':[0,0,0]},'b':{'position':[4,0,0]}},'player':{'position':[0,0,3]},'objects':{},'observations':{'a':{'person/player':{},'person/b':{}}}}}
        self.behaviors=[{'person':'player','behavior':'follow_actor'},{'person':'b','behavior':'stay'}]
        raw=json.dumps(self.definition,ensure_ascii=False)
        self.package={'definition':self.definition,'receipt':{'verifier':'leader-luau-tests-v1','passed':True,'definition_json':raw,'definition_sha256':hashlib.sha256(raw.encode()).hexdigest()}}
        self.status={'state':'ready','review':{'passed':True,'outcomes':{'participant_behaviors':self.behaviors}}}
        self.write('package.json',self.package);self.write('status.json',self.status)
        self.write('outcome_plan.json',{'participant_behaviors':self.behaviors})
        self.write('build_request.json',{'verification_snapshot':{'person_id':'a'}})

    def write(self,name,value):
        (self.old/name).write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')

    def test_approved_full_definition_without_images_supplies_premises(self):
        evidence=outcomes.approved_baseline_preconditions(self.request,self.folder.parent)
        self.assertTrue(evidence['available']);self.assertEqual(evidence['participant_behaviors'],self.behaviors)
        self.assertEqual(evidence['origin']['job'],'job_approved')
        self.assertEqual(evidence['origin']['revision_ref'],'escort@approved')
        self.assertNotIn('position',json.dumps(evidence))

    def test_rejects_unapproved_corrupt_and_merely_same_source_records(self):
        for change in ('failed','review_failed','receipt_failed','hash','definition','plan'):
            with self.subTest(change=change):
                package=copy.deepcopy(self.package);status=copy.deepcopy(self.status)
                plan={'participant_behaviors':self.behaviors}
                if change=='failed':status['state']='failed'
                if change=='review_failed':status['review']['passed']=False
                if change=='receipt_failed':package['receipt']['passed']=False
                if change=='hash':package['receipt']['definition_sha256']='wrong'
                if change=='definition':self.request['revision']['definition']=dict(self.definition,name='别的完整定义')
                if change=='plan':plan={'participant_behaviors':[]}
                self.write('package.json',package);self.write('status.json',status);self.write('outcome_plan.json',plan)
                self.assertFalse(outcomes.approved_baseline_preconditions(self.request,self.folder.parent)['available'])
                self.request['revision']['definition']=self.definition

    def test_cross_actor_only_known_fixed_player_is_unambiguous(self):
        self.write('build_request.json',{'verification_snapshot':{'person_id':'other_actor'}})
        evidence=outcomes.approved_baseline_preconditions(self.request,self.folder.parent)
        self.assertEqual(evidence['participant_behaviors'],self.behaviors[:1])
        self.assertEqual(evidence['unmapped_participants'][0]['person'],'b')
        self.request['verification_snapshot']['observations']['a'].clear()
        self.assertEqual(outcomes.approved_baseline_preconditions(self.request,self.folder.parent)['participant_behaviors'],[])
        self.request['character_context']['id']='wrong_actor'
        with self.assertRaises(ValueError):outcomes.approved_baseline_preconditions(self.request,self.folder.parent)

    def test_planner_cannot_silently_drop_premises_but_can_explain_new_goal(self):
        plan={'checks':[],'semantic_requirements':['双方共同到达'],'participant_behaviors':[]}
        with patch.object(outcomes,'complete',return_value={'ok':True,'text':json.dumps(plan)}) as model:
            with self.assertRaisesRegex(ValueError,'前提'):outcomes.prepare(self.folder,self.request,{})
            payload=json.loads(model.call_args.args[0].split('\n')[-1])
            self.assertEqual(payload['baseline_preconditions']['participant_behaviors'],self.behaviors)
            self.assertEqual(payload['original'],self.request['revision']['player_event'])
        self.assertFalse((self.folder/'outcome_plan.json').exists())
        plan['baseline_adjustment']='本次只验证双方停留时的中断分支，玩家不跟随。'
        with patch.object(outcomes,'complete',return_value={'ok':True,'text':json.dumps(plan)}):
            outcomes.prepare(self.folder,self.request,{})
        published=json.loads((self.folder/'verification_preconditions.json').read_text(encoding='utf-8'))
        self.assertEqual(published['baseline_participant_behaviors'],[])
        self.assertEqual(published['baseline_preconditions']['origin']['actor_id'],'a')
        self.assertEqual(published['baseline_adjustment'],plan['baseline_adjustment'])


class OutcomeTests(unittest.TestCase):
    def test_current_world_contract_covers_every_declared_operation(self):
        import re
        source=(Path(__file__).resolve().parents[2]/'scripts/skills/luau_contract.gd').read_text(encoding='utf-8')
        declared=json.loads(re.search(r'const OPERATIONS=(\[.*\])',source).group(1))
        contract=outcomes.world_contract()
        self.assertEqual(set(contract['operations']),set(declared))
        self.assertIn('recipient_id',contract['execution_progress'])

    def test_every_observation_keeps_current_visibility_and_position(self):
        source={'runtime':{'trace':[
            {'operation':'perceive','result':{'ok':True,'observation_id':'one','near':{'landmarks':{'person/b':{'kind':'person','visible_now':True,'position':{'x':0,'y':0,'z':3}}}}}},
            {'operation':'approach','result':{'ok':True}},
            {'operation':'perceive','result':{'ok':True,'observation_id':'two','near':{'landmarks':{}}}}]}}
        packet=motion_review.execution_evidence(source)
        first=packet['runtime']['trace'][0]['result']
        self.assertEqual(first['observation_id'],'one')
        self.assertTrue(first['near']['landmarks']['person/b']['visible_now'])
        self.assertEqual(first['near']['landmarks']['person/b']['position']['z'],3)
        self.assertEqual(packet['runtime']['trace'][2]['result']['near']['landmarks'],{})
        self.assertEqual(packet['runtime']['trace'][1],source['runtime']['trace'][1])

    def test_historical_review_deduplicates_only_identical_execution(self):
        old={'source_event_id':'old','runtime':{'trace':[{'operation':'approach','result':{'ok':True}}]},'validation_cases':[{'name':'resume','steps':[]}]}
        different=copy.deepcopy(old);different['source_event_id']='another'
        review={'passed':False,'issues':['理由',copy.deepcopy(old),different]}
        compact=motion_review.review_without_duplicate_execution(review,old)
        self.assertEqual(compact['issues'][0],'理由')
        self.assertEqual(compact['issues'][1]['execution_reference'],'revision_comparison.previous_execution')
        self.assertEqual(compact['issues'][2],different)
        self.assertEqual(review['issues'][1],old,'本地原始审查不修改')

    def test_repair_feedback_keeps_fixture_behavior_without_global_movement_coordinates(self):
        source={'runtime':{'returned':{'ok':False}},'participant_fixture':{'behaviors':{'player':'stay'},
                'distance_walked':{'player':3},'source':'test_double','samples':[{'position':[100,0,30]}]}}
        feedback=motion_review.repair_evidence(source)
        self.assertEqual(feedback['participant_fixture']['behaviors'],{'player':'stay'})
        self.assertNotIn('samples',feedback['participant_fixture'])
        self.assertIn('samples',source['participant_fixture'])

    def test_replay_budget_counts_calls_but_never_extends_learning_deadline(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            self.assertEqual(motion_review.replay_budget(folder,660)['timeout_seconds'],165)
            (folder/'verification_cases.json').write_text(json.dumps([{'steps':[{},{}]},{'steps':[{}, {},{}]}]))
            value=motion_review.replay_budget(folder,430)
            self.assertEqual(value['planned_invocations'],6)
            self.assertEqual(value['timeout_seconds'],235)
            self.assertEqual(value['scene_timeout_seconds'],225)
            self.assertEqual(value['semantic_reserve_seconds'],195)
            self.assertLessEqual(value['timeout_seconds']+value['semantic_reserve_seconds'],430)
            self.assertLess(motion_review.replay_budget(folder,40)['timeout_seconds'],15)
            self.assertEqual(motion_review.replay_budget(folder,40)['timeout_seconds'],0)
            self.assertEqual(motion_review.replay_budget(folder,40)['scene_timeout_seconds'],0)
            # 已测七次完整调用需要约448秒，保留正常审查时限后仍能进入完整回放。
            value=motion_review.replay_budget(folder,750)
            self.assertGreaterEqual(value['scene_timeout_seconds'],448)
            self.assertLessEqual(value['timeout_seconds']+value['semantic_reserve_seconds'],750)

    def test_budget_inspection_counts_current_declaration_not_old_job_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            (folder/'verification_cases.json').write_text(json.dumps([{'steps':[{}]*12}]))
            self.assertEqual(motion_review.replay_budget(folder,750,[])['planned_invocations'],1)
            value=motion_review.replay_budget(folder,750,[{'steps':[{},{}]}])
            self.assertEqual(value['planned_invocations'],3)
            self.assertEqual(value['scene_timeout_seconds'],485)

    def test_participant_behavior_is_fixed_by_independent_plan_and_known_snapshot(self):
        request={'verification_snapshot':{'person_id':'a','people':{'a':{'needs':{},'position':[0,0,0]},'b':{'position':[4,0,0]},'hidden':{'position':[1,0,0]}},'player':{'position':[0,0,3]},'objects':{},'observations':{'a':{'person/player':{},'person/b':{}}}}}
        before=outcomes.baseline(request)
        self.assertEqual(set(before['participants']),{'player','b'})
        plan={'checks':[],'semantic_requirements':['双方到达目标'], 'participant_behaviors':[{'person':'player','behavior':'follow_actor'}]}
        self.assertEqual(outcomes.validate(plan,before),plan)
        for change in [{'person':'hidden','behavior':'follow_actor'},{'person':'a','behavior':'follow_actor'},{'person':'player','behavior':'teleport'},{'person':'player','behavior':'follow_actor','speed':100}]:
            with self.assertRaises(ValueError):outcomes.validate(dict(plan,participant_behaviors=[change]),before)
        with self.assertRaises(ValueError):outcomes.validate(dict(plan,participant_behaviors=plan['participant_behaviors']*2),before)

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
            self.assertEqual(payload['world_contract'],outcomes.world_contract())
            self.assertIn('玩家',payload['world_contract']['operations']['handover'])
            self.assertIn('直接接收',payload['world_contract']['operations']['handover'])
            self.assertIn('recipient_id',payload['world_contract']['execution_progress'])
            self.assertIn('不能作为加载前的前置条件',payload['review_stage']['boundary'])

    def test_planning_keeps_goal_environment_and_methods_without_role_history(self):
        context={'id':'a','name':'月亮','space_observation':{'far_field':{'fruit_area':{'position':{'x':50,'y':0,'z':20},'error_m':5}}},
                 'survival_observation':{'held_objects':[]},'visible_people':[{'id':'player'}],
                 'available_skills':[{'id':'go_to_known','description':'按本人线索走近'}],
                 'working_context':{'recent_turns':['无关的旧经历'*60000]},'relationships':{'private_personal_judgment':'不用于世界结果验收'}}
        original={'text':'带我去果树林，掉队时等待；学会后再演示。'}
        request={'verification_snapshot':{'person_id':'a','people':{'a':{'needs':{},'position':[0,0,0]}},'objects':{}},
                 'character_context':context,'creation':{'goal':'持续带路','player_event':original}}
        plan={'checks':[],'semantic_requirements':['依据实际位置确认共同到达，等待后继续']}
        with tempfile.TemporaryDirectory() as tmp,patch.object(outcomes,'complete',return_value={'ok':True,'text':json.dumps(plan)}) as model:
            outcomes.prepare(Path(tmp),request,{})
            prompt=model.call_args.args[0];payload=json.loads(prompt.split('\n')[-1])
            self.assertLess(len(prompt),10000)
            self.assertEqual(payload['original'],original)
            self.assertEqual(payload['before'],outcomes.baseline(request))
            for key in ('space_observation','survival_observation','visible_people','available_skills'):
                self.assertEqual(payload['character_context'][key],context[key])
            self.assertNotIn('working_context',payload['character_context'])
            self.assertIn('working_context',request['character_context'],'角色/编写上下文不被修改')

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

    def test_review_keeps_early_route_evidence_and_all_actions_without_mutating_raw_trace(self):
        source={'runtime':{'trace':[
            {'operation':'walk_options','result':{'ok':True,'observation_id':'old',
             'odometry':{'position':{'x':0,'y':0,'z':0}},'request_odometry':{'request_id':'request'},
             'known':{'target':{'approx_position':{'x':20,'y':0,'z':10},'position_error_per_axis_m':5}},
             'near':{'view':{'half_angle_degrees':80},'landmarks':{'person/player':{'visible_now':True}},
                     'ground_samples':[{'probe':{'x':0,'z':1},'position':{'x':0,'y':0,'z':1},'state':'visible_surface','slope_degrees':0,'path_clear':True}]}}},
            {'operation':'grasp','result':{'ok':True}},
            {'operation':'walk_options','result':{'ok':True,'observation_id':'latest','near':{'ground_samples':[]}}},
            {'operation':'check_placement','result':{'ok':False,'code':'no_support'}}]}}
        original=copy.deepcopy(source)
        packet=motion_review.execution_evidence(source)
        expected=copy.deepcopy(source)
        del expected['runtime']['trace'][0]['result']['near']['ground_samples'][0]['probe']
        self.assertEqual(packet,expected)
        self.assertEqual(source,original)
        nested=motion_review.execution_evidence({'validation_cases':[{'name':'resume','steps':[source]}]})
        self.assertEqual(nested['validation_cases'][0]['steps'][0],expected)

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

    def test_repair_feedback_keeps_continuous_case_provenance(self):
        step={'source_event_id':'request_original','resume_from_step':0,
              'preparation':[],'transitions':[{'operation':'consume_contents','occurrence':1,'preparation':[{'person':'player','position':[0,0,6]}]}],
              'before':{'hidden_other_state':1},'after':{'hidden_other_state':2},
              'runtime':{'returned':{'ok':True}},'facts':[{'source_event_id':'request_original','kind':'given'}]}
        packet=motion_review.repair_evidence({'validation_cases':[{'name':'resume','steps':[step]}]})
        result=packet['validation_cases'][0]['steps'][0]
        self.assertEqual(result['source_event_id'],'request_original')
        self.assertEqual(result['resume_from_step'],0)
        self.assertEqual(result['transitions'],step['transitions'])
        self.assertNotIn('before',result);self.assertNotIn('after',result)

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

    def test_indexed_codex_review_preserves_facts_and_still_requires_semantic_approval(self):
        for approved in (True,False):
            with self.subTest(approved=approved):
                self._review(self.after,approved,True,visual_pass=approved,codex_cli=True)

    def _review(self,after,passed,visual_called,visual_pass=True, transient=False, hard_error=False,codex_cli=False):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'motion_1';output.mkdir()
            (folder/'build_request.json').write_text(json.dumps({'owned_skills':{}}))
            (folder/'candidate_definition.json').write_text(json.dumps({'dependencies':{}}))
            (output/'code_scope.json').write_text(json.dumps({'entry':{'dependencies':{},'program_json':json.dumps({'source':'return function() return {ok=true} end'})},'definitions':{}}))
            (folder/'outcome_plan.json').write_text(json.dumps(self.plan))
            preconditions={'baseline_participant_behaviors':[],
                           'baseline_preconditions':{'origin':{'job':'job_approved'}},
                           'baseline_adjustment':'当前目标只验证放下，不再要求玩家跟随。'}
            (folder/'verification_preconditions.json').write_text(json.dumps(preconditions),encoding='utf-8')
            (folder/'source.luau').write_text('return function() return {ok=true} end')
            data={'passed':True,'faults':[],'frames':[{'file':'frame.jpg','time_ms':1,'stage':'释放'}],'all_frames':[],'samples':[],'note':'fixture',
                  'result':{'before':self.before,'after':after,'runtime':{'returned':{'ok':True}}}}
            (output/'motion.json').write_text(json.dumps(data))
            decision={'passed':visual_pass,'owner':'skill','issues':[] if visual_pass else ['动作不符合要求']}
            responses=[{'ok':True,'text':json.dumps(decision)}]
            if transient:responses.insert(0,{'ok':False,'retryable':True,'error':'HTTP 503'})
            if hard_error:responses=[{'ok':False,'error':'HTTP 403'}]
            with patch.object(motion_review,'run_hidden',return_value=SimpleNamespace(stdout='',stderr='',returncode=0)),patch.object(motion_review,'complete',side_effect=responses) as model:
                result=motion_review.review(folder,{'protocol':'codex_cli'} if codex_cli else {},folder,'fixture',1,goal='放到篮子旁')
            self.assertEqual(result['passed'],passed)
            self.assertEqual(model.called,visual_called)
            if visual_called:
                packet=model.call_args.args[1]['analysis_evidence'] if codex_cli else None
                text=json.dumps(packet,ensure_ascii=False) if codex_cli else model.call_args.args[0]
                self.assertIn('candidate_preflight',text)
                self.assertIn('不能作为加载前的前置条件',text)
                self.assertIn('当前目标只验证放下',text)
                self.assertIn('job_approved',text)
                if codex_cli:
                    self.assertEqual(packet['execution']['before'],self.before)
                    self.assertEqual(packet['execution']['after'],after)
                    self.assertIn('放到篮子旁',model.call_args.args[0])
                    self.assertNotIn('world_outcomes',model.call_args.args[0])
            if visual_called:self.assertEqual(model.call_count,2 if transient else 1)
            self.assertTrue((output/'review.json').exists())
            if hard_error:self.assertEqual(json.loads((output/'review.json').read_text())['issues'],['HTTP 403'])
            self.assertTrue((output/'outcomes.json').exists())
            (folder/'status.json').write_text(json.dumps({'state':'ready' if passed else 'failed','review':result}))
            page=write_report(folder).read_text(encoding='utf-8')
            self.assertIn('隔离回放证据',page)
            if visual_called:
                self.assertEqual(model.call_args.kwargs['images'],[])
                if not hard_error:self.assertEqual(result['review_mode'],'world_semantics')

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
