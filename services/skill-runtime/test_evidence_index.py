import copy,json,unittest
from evidence_index import EvidenceIndex

class IndexTests(unittest.TestCase):
    def test_classification_and_lossless_details(self):
        files={}
        index=EvidenceIndex(lambda name,value:files.__setitem__(name,value))
        steps=[{'operation':'approach' if i%2==0 else 'grasp','arguments':{'n':i},
                'result':{'ok':False,'code':'blocked','observation':'x'*4000}} for i in range(30)]
        raw={'runtime':{'trace':steps},'facts':[{'quantity':1}]}
        before=copy.deepcopy(raw)
        summary=index.pack(raw)
        def expand(v):
            if isinstance(v,dict):
                if 'evidence_file'in v:return expand(files[v['evidence_file']])
                if 'text_length'in v:return ''.join(expand(x) for x in v['parts'])
                if 'count'in v and 'pages'in v:return sum((expand(x) for x in v['pages']),[])
                return {k:expand(x) for k,x in v.items()}
            if isinstance(v,list):return [expand(x) for x in v]
            return v
        runtime=expand(summary)['runtime']
        self.assertEqual(set(runtime['trace']),{'navigation','holding'})
        entries=[]
        for group in runtime['trace'].values():
            # category descriptor expands directly into chronological step descriptors.
            entries.extend(group)
        # each descriptor is itself a direct evidence link, preserving raw complete step.
        self.assertEqual(len(entries),30)
        self.assertEqual(sorted(x['arguments']['n'] for x in entries),list(range(30)))
        self.assertTrue(all(x['result']['observation']=='x'*4000 for x in entries))
        self.assertEqual(raw,before)
        self.assertLess(len(json.dumps(summary)),500)
        self.assertTrue(all(len(json.dumps(v))<12000 for v in files.values()))

if __name__=='__main__':unittest.main()
