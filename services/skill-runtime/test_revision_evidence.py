import json
import tempfile
import unittest
from pathlib import Path
from revision_evidence import collect


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.revision={'ref':'drink@version','feedback':'改成举高手',
            'player_event':{'id':'original','text':'不要举到头顶，手停在嘴前。'},
            'definition':{'program_json':json.dumps({'source_sha256':'correct'})}}

    def make_motion(self,sha):
        job=self.root/'job_test';motion=job/'motion_1';motion.mkdir(parents=True)
        (job/'candidate.json').write_text(json.dumps({'source_sha256':sha}))
        (motion/'frame_00.jpg').write_bytes(b'fixture')
        (motion/'motion.json').write_text(json.dumps({'frames':[{'file':'frame_00.jpg','time_ms':10}]}))
        return motion

    def test_original_and_matching_evidence(self):
        self.make_motion('correct')
        packet,images=collect(self.revision,{'execution_results':[{'skill_ref':'wrong'},{'skill_ref':'drink@version'}]},self.root)
        self.assertEqual(packet['trigger_event']['text'],'不要举到头顶，手停在嘴前。')
        self.assertEqual(packet['daily_model_interpretation'],'改成举高手')
        self.assertEqual(len(packet['execution_results']),1)
        self.assertEqual(len(images),1)

    def test_wrong_version_is_not_attached(self):
        self.make_motion('other')
        packet,images=collect(self.revision,{},self.root)
        self.assertFalse(packet['visual_evidence']['available'])
        self.assertEqual(images,[])

    def test_paths_cannot_escape_capture(self):
        motion=self.make_motion('correct')
        (motion/'motion.json').write_text(json.dumps({'frames':[{'file':'../../outside.jpg'}]}))
        self.assertEqual(collect(self.revision,{},self.root)[1],[])

    def test_missing_evidence_is_explicit(self):
        packet,images=collect(self.revision,{},self.root)
        self.assertFalse(packet['visual_evidence']['available'])
        self.assertEqual(packet['trigger_event'],self.revision['player_event'])
