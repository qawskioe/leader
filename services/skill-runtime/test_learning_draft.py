import json
from pathlib import Path
import sys,tempfile,unittest,os
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
                (folder/'candidate_definition.json').write_text(json.dumps({'program_json':json.dumps({'source':name}),'parameters':{}}))
            packet=failed_draft(current,request)
            self.assertEqual(packet['source'],'own')
            self.assertIn('尚未掌握',packet['meaning'])
            self.assertFalse((current/'package.json').exists())
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

if __name__=='__main__':unittest.main()
