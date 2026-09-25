import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'text-gateway'))
from motion_review import revision_comparison


class ReviewComparisonTests(unittest.TestCase):
    def test_failed_draft_reaches_reviewer_without_becoming_current_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            (folder/'build_request.json').write_text('{}')
            draft={'source':'return old','job':'job_old','previous_execution':{'runtime':{'returned':{'ok':False},'trace':[{'operation':'grasp','result':{'ok':True}}]}}}
            draft['previous_review']={'passed':False,'issues':['抓握已经执行，落稳未通过']}
            (folder/'previous_failed_draft.json').write_text(json.dumps(draft))
            evidence=revision_comparison(folder,'return new')
            self.assertEqual(evidence['origin']['job'],'job_old')
            self.assertIn('-return old',evidence['source_diff'])
            self.assertIn('+return new',evidence['source_diff'])
            self.assertFalse(evidence['previous_execution']['runtime']['returned']['ok'])
            self.assertEqual(evidence['previous_review'],draft['previous_review'])
            self.assertEqual(draft['previous_execution']['runtime']['trace'][0]['result'],{'ok':True})

    def test_owned_revision_and_missing_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            (folder/'build_request.json').write_text('{}')
            self.assertFalse(revision_comparison(folder,'new')['available'])
            request={'revision':{'ref':'owned@old','definition':{'program_json':json.dumps({'source':'old'})}}}
            (folder/'build_request.json').write_text(json.dumps(request))
            evidence=revision_comparison(folder,'new')
            self.assertEqual(evidence['origin']['ref'],'owned@old')
            self.assertIsNone(evidence['previous_execution'])

if __name__=='__main__': unittest.main()
