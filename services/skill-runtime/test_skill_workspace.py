import json,tempfile,unittest
from pathlib import Path
from skill_workspace import Workspace
from development_backend import read_selection,linux_path

class WorkspaceTests(unittest.TestCase):
    def test_game_owned_artifacts_git_and_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            preconditions={'baseline_participant_behaviors':[{'person':'player','behavior':'follow_actor'}],
                           'baseline_preconditions':{'origin':{'job':'job_approved'}},'baseline_adjustment':''}
            (Path(tmp)/'verification_preconditions.json').write_text(json.dumps(preconditions),encoding='utf-8')
            w=Workspace(Path(tmp),{'goal_id':'g','world_operations':[],'character_context':{},'owned_skills':{}},{'source':'return 1','name':'test'},'sdk',{}, {})
            self.assertEqual(json.loads(w.path('reference/verification_preconditions.json').read_text(encoding='utf-8')),preconditions)
            self.assertEqual(w.verification_preconditions,preconditions)
            with self.assertRaises(ValueError):w.path('reference/verification_preconditions.json',write=True)
            self.assertEqual(w.path('reference/principles.md').read_text(encoding='utf-8'),Path(__file__).with_name('authoring_principles.md').read_text(encoding='utf-8'))
            with self.assertRaises(ValueError):w.path('reference/principles.md',write=True)
            (w.root/'source.luau').write_text('return 2')
            self.assertIn('+return 2',w.git('diff',w.base))
            ref=w.checkpoint('tested')
            self.assertEqual(w.git('show',ref+':source.luau'),'return 2')
            self.assertNotEqual(w.digest(),'')
            for path in ['../secret','.git/config','C:/secret']:
                with self.assertRaises(ValueError):w.path(path)
            with self.assertRaises(ValueError):w.export('../outside','bad')
            (w.root/'source.luau').write_text('x'*60001)
            with self.assertRaises(ValueError):w.output()

    def test_selection_is_explicit_no_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.assertEqual(read_selection(root),{'backend':'disabled'})
            p=root/'services/skill-runtime/runtime/development_backend.json';p.parent.mkdir(parents=True)
            p.write_text(json.dumps({'backend':'unknown'}))
            with self.assertRaises(ValueError):read_selection(root)
            p.write_text(json.dumps({'backend':'opencode','runtime':'wsl','executable':'/a/opencode'}))
            self.assertEqual(read_selection(root)['backend'],'opencode')
            p.write_text(json.dumps({'backend':'opencode'}))
            with self.assertRaises(ValueError):read_selection(root)

    def test_windows_path_translation(self):
        self.assertEqual(linux_path('D:\\Leader\\space dir\\a.py'),'/mnt/d/Leader/space dir/a.py')
        self.assertEqual(linux_path('/tmp/a'),'/tmp/a')
        with self.assertRaises(ValueError):linux_path('relative')

if __name__=='__main__':unittest.main()
