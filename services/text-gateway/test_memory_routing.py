import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run

class RoutingTests(unittest.TestCase):
    def test_long_day_context_is_not_rejected_at_old_limit(self):
        body=run.DecisionRequest(mode='decision',prompt='当日记录'*16000)
        self.assertEqual(len(body.prompt),64000)
        with self.assertRaises(ValueError):
            run.DecisionRequest(mode='decision',prompt='x'*250001)

    def test_routes_are_separate_and_request_cannot_override_provider(self):
        calls=[]
        def complete(prompt,config=None):
            calls.append(config)
            return {'ok':True,'text':'{}'}
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'runtime').mkdir()
            (root/'runtime/gateway-key.txt').write_text('fixture')
            (root/'runtime/memory_model.json').write_text(json.dumps({'model':'fast-fixture'}))
            with patch.object(run,'ROOT',root),patch.object(run,'complete',complete):
                asyncio.run(run.decision(run.DecisionRequest(mode='memory',prompt='recall?'),'Bearer fixture'))
                asyncio.run(run.decision(run.DecisionRequest(mode='decision',prompt='act?'),'Bearer fixture'))
                self.assertEqual(calls,[{'model':'fast-fixture'},None])
                (root/'runtime/memory_model.json').unlink()
                result=asyncio.run(run.decision(run.DecisionRequest(mode='memory',prompt='recall?'),'Bearer fixture'))
                self.assertFalse(result['ok'])
                self.assertEqual(len(calls),2)
        with self.assertRaises(ValueError):
            run.DecisionRequest(mode='memory',prompt='x',model='override')

if __name__=='__main__':unittest.main()
