import json
from pathlib import Path
import sys,tempfile,unittest,os
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from learning_draft import failed_draft

class DraftTests(unittest.TestCase):
    def test_only_same_person_and_goal_failed_code_can_be_reused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir()
            request={'goal_id':'gesture','verification_snapshot':{'person_id':'a'}}
            for name,person,goal,state in [('own','a','gesture','failed'),('other','b','gesture','failed'),('wrong_goal','a','drink','failed'),('ready','a','gesture','ready')]:
                folder=root/('job_'+name);folder.mkdir()
                (folder/'status.json').write_text(json.dumps({'state':state}))
                (folder/'build_request.json').write_text(json.dumps({'goal_id':goal,'verification_snapshot':{'person_id':person}}))
                (folder/'draft_context.json').write_text(json.dumps({'schema':1,'goal_id':goal,'person_id':person,'goal':'测试草稿'}))
                (folder/'candidate_definition.json').write_text(json.dumps({'program_json':json.dumps({'source':name}),'parameters':{}}))
            packet=failed_draft(current,request)
            self.assertEqual(packet['source'],'own')
            self.assertIn('尚未掌握',packet['meaning'])
            self.assertFalse((current/'package.json').exists())
    def test_revision_draft_requires_same_accepted_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir()
            request={'goal_id':'g','verification_snapshot':{'person_id':'a'},'revision':{'ref':'g@v1'}}
            old=root/'job_old';old.mkdir()
            (old/'status.json').write_text(json.dumps({'state':'failed'}))
            (old/'build_request.json').write_text(json.dumps(request))
            (old/'draft_context.json').write_text(json.dumps({'schema':1,'goal_id':'g','person_id':'a','goal':'测试修订'}))
            (old/'candidate_definition.json').write_text(json.dumps({'revision_of':'g@v1','program_json':json.dumps({'source':'failed revision'}),'parameters':{}}))
            self.assertEqual(failed_draft(current,request)['source'],'failed revision')
            request['revision']['ref']='g@v2'
            self.assertEqual(failed_draft(current,request),{})
            request.pop('revision')
            self.assertEqual(failed_draft(current,request),{})

    def test_missing_or_damaged_draft_does_not_become_a_skill(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir()
            damaged=root/'job_damaged';damaged.mkdir();(damaged/'status.json').write_text('{')
            self.assertEqual(failed_draft(current,{'goal_id':'g','verification_snapshot':{'person_id':'a'}}),{})

    def test_latest_timeout_does_not_inherit_previous_candidate_motion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir()
            old=root/'job_old';old.mkdir()
            request={'goal_id':'g','verification_snapshot':{'person_id':'a'}}
            (old/'status.json').write_text(json.dumps({'state':'failed'}))
            (old/'build_request.json').write_text(json.dumps(request))
            (old/'draft_context.json').write_text(json.dumps({'schema':1,'goal_id':'g','person_id':'a','goal':'测试超时'}))
            (old/'candidate_definition.json').write_text(json.dumps({'program_json':json.dumps({'source':'third version'}),'parameters':{}}))
            first=old/'motion_2';first.mkdir()
            (first/'motion.json').write_text(json.dumps({'result':{'runtime':{'returned':{'code':'old error'}}}}))
            (first/'review.json').write_text(json.dumps({'owner':'skill','issues':['old error']}))
            os.utime(first/'review.json',(10,10))
            latest=old/'motion_3';latest.mkdir()
            (latest/'review.json').write_text(json.dumps({'owner':'executor','issues':['timeout']}))
            packet=failed_draft(current,request)
            self.assertEqual(packet['source'],'third version')
            self.assertEqual(packet['previous_review']['owner'],'executor')
            self.assertNotIn('previous_execution',packet)

    def test_compact_identity_skips_unrelated_large_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir()
            for name,person in [('own','a'),('other','b')]:
                folder=root/('job_'+name);folder.mkdir()
                (folder/'status.json').write_text(json.dumps({'state':'failed'}))
                (folder/'draft_context.json').write_text(json.dumps({'schema':1,'person_id':person,'goal_id':'g','goal':'测试'}))
                (folder/'build_request.json').write_text('invalid full request: never read')
                (folder/'candidate_definition.json').write_text(json.dumps({'program_json':json.dumps({'source':name}),'parameters':{}}))
            original=Path.read_text
            def guarded(path,*args,**kwargs):
                self.assertNotEqual(path.name,'build_request.json','草稿选择不得读取大型请求包')
                return original(path,*args,**kwargs)
            with patch.object(Path,'read_text',guarded):
                self.assertEqual(failed_draft(current,{'goal_id':'g','verification_snapshot':{'person_id':'a'}})['source'],'own')

    def test_retry_preserves_candidate_verification_cases(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);current=root/'job_current';current.mkdir();old=root/'job_old';old.mkdir()
            (old/'status.json').write_text(json.dumps({'state':'failed'}))
            (old/'draft_context.json').write_text(json.dumps({'schema':1,'person_id':'a','goal_id':'g','goal':'测试'}))
            definition={'name':'方法','description':'测试方法','parameters':{},'parameter_kinds':{},'dependencies':{},'program_json':json.dumps({'source':'return function() end','capabilities':[]})}
            (old/'candidate_definition.json').write_text(json.dumps(definition))
            (old/'test_arguments.json').write_text('{}')
            cases=[{'name':'after_delivery','steps':[{'conditions':[],'arguments':{}},{'conditions':[],'resume_previous':True}]}]
            (old/'verification_cases.json').write_text(json.dumps(cases))
            packet=failed_draft(current,{'goal_id':'g','verification_snapshot':{'person_id':'a'}})
            self.assertEqual(packet['candidate_output']['verification_cases'],cases)
            self.assertFalse((current/'package.json').exists())

if __name__=='__main__':unittest.main()
