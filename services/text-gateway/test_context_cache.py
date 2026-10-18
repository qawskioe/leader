import copy
import io
import json
import unittest
from unittest.mock import patch
import text_model
from context_cache import ContextCache, changes, restore


class ContextCacheTests(unittest.TestCase):
    config={'url':'https://fixture.invalid','key':'fixture','model':'gpt-6.1-sol','context_cache':True,'context_scope':'fixture-world'}

    def context(self, person='person_001'):
        return {'self': {'id':person, 'identity':{'description':'真实身份'*1200},
                         'needs':{'hunger':80}, 'current_action':{'target':'basket/1'},
                         'relationships':{'person_002':{'trust':0.75}},
                         'memory_access':{'available_counts':{'heard':3}},
                         'working_context':{'recent_turns':[{'event':{'id':'old_event'}}],
                                            'last_known_locations':{'basket/1':{'x':0.123456789}}}},
                'current_event':{'id':'new_event','text':'你有多饿？'}}

    def prepare(self, cache, current, **kwargs):
        packet=cache.prepare(json.dumps(current,ensure_ascii=False)+kwargs.pop('suffix',''),
                             kwargs.pop('prefix','rules'),kwargs.pop('reference','catalog'),
                             kwargs.pop('config',self.config))
        cache.confirm(packet['key'],packet['diagnostic']['base_id'])
        return packet

    def test_lossless_updates_cover_empty_values_types_arrays_and_removals(self):
        base={'self':{'needs':1,'array':[1,2],'empty':'old','removed':True},'current_event':{}}
        current={'self':{'needs':1.0,'array':[2,1],'empty':None,'new':False},'current_event':{'id':'fresh'}}
        sets,removed=changes(base,current)
        updated=restore(base,{'set':sets,'remove':removed,'current_event':current['current_event']})
        self.assertEqual(updated,current)
        self.assertIsInstance(updated['self']['needs'],float)
        self.assertEqual(base['self']['array'],[1,2])

    def test_updated_scene_uses_identical_base_and_fresh_event(self):
        cache=ContextCache();base=self.context();a=self.prepare(cache,base)
        current=copy.deepcopy(base);current['self']['needs']['hunger']=17
        current['self']['current_action']={};current['current_event']={'id':'second','text':'拿远一点'}
        b=self.prepare(cache,current)
        self.assertEqual(a['messages'][0],b['messages'][0]);self.assertEqual(a['key'],b['key'])
        self.assertEqual(b['diagnostic']['mode'],'update')
        self.assertEqual(restore(base,json.loads(b['messages'][1])['context_update']),current)
        self.assertLess(b['diagnostic']['new_context_chars'],len(json.dumps(current))*0.1)

    def test_rebound_frames_only_update_changed_values_inside_layout_arrays(self):
        cache=ContextCache();base=self.context()
        base['self']['identity']['description']='人物身份'
        locations=base['self']['working_context']['last_known_locations']
        locations.clear()
        for index in range(34):
            locations[str(index)]={'record_ref':'location_layout','values':['frame1',index*0.125,0.123456789,'旧观察及来源'*30]}
        first=self.prepare(cache,base);current=copy.deepcopy(base)
        for value in current['self']['working_context']['last_known_locations'].values():value['values'][0]='frame2'
        current['current_event']={'id':'next','text':'核对本轮现场'}
        packet=self.prepare(cache,current)
        self.assertEqual(packet['diagnostic']['mode'],'update','只换观察帧不应重新发送整份地点布局')
        self.assertEqual(first['messages'][0],packet['messages'][0])
        update=json.loads(packet['messages'][-1])['context_update']
        self.assertEqual(restore(base,update),current)
        self.assertLess(packet['diagnostic']['new_context_chars'],len(json.dumps(current,ensure_ascii=False))*0.5)
        self.assertTrue(any(isinstance(part,int) for item in update['set'] for part in item['path']))

    def test_array_updates_preserve_order_length_types_and_nested_removals(self):
        for old,new in [
            ([{'keep':'x'*400,'removed':1,'value':True}],[{'keep':'x'*400,'value':1}]),
            ([{'keep':'x'*400,'value':1}],[{'keep':'x'*400,'value':1.0}]),
            ([1,2,3],[3,2,1]),([1,2],[1,2,3]),([1,2],[]),
            ([['a','b']],[['b','a']]),([None,False],[False,None])]:
            base={'self':{'values':old},'current_event':{}}
            current={'self':{'values':new},'current_event':{'id':'next'}}
            frozen=copy.deepcopy(base)
            sets,removed=changes(base,current)
            rebuilt=restore(base,{'set':sets,'remove':removed,'current_event':current['current_event']})
            self.assertEqual(json.dumps(rebuilt,sort_keys=True),json.dumps(current,sort_keys=True))
            self.assertEqual(base,frozen)

    def test_space_skill_availability_and_original_task_are_preserved(self):
        cache=ContextCache();base=self.context()
        base['self']['space_observation']={'id':'frame1','objects':[{'id':'basket/1','position':{'x':0.123456789,'y':0.0,'z':2.4}}]}
        base['self']['available_skills']=[{'ref':'skill1','callable':True}]
        base['self']['working_context']['task']={'request':{'text':'放远一点'},'progress':[{'quantity':1}]}
        self.prepare(cache,base);current=copy.deepcopy(base)
        current['self']['space_observation']={'id':'frame2','objects':[{'id':'basket/1','position':{'x':-1.987654321,'y':0.02,'z':3.7}}]}
        current['self']['available_skills'][0]['callable']=False
        current['self']['working_context']['task']['progress'].append({'quantity':2})
        packet=self.prepare(cache,current)
        self.assertEqual(restore(base,json.loads(packet['messages'][-1])['context_update']),current)
        self.assertEqual(current['self']['working_context']['task']['request']['text'],'放远一点')

    def test_people_and_provider_credentials_are_isolated(self):
        cache=ContextCache();a=self.prepare(cache,self.context())
        for context,config in [(self.context('person_002'),self.config),
                               (self.context(),dict(self.config,key='other')),
                               (self.context(),dict(self.config,model='other'))]:
            b=self.prepare(cache,context,config=config)
            self.assertNotEqual(a['key'],b['key']);self.assertEqual(len(b['messages']),1)
        self.assertNotIn('fixture',a['key'])

    def test_changed_skill_catalog_starts_new_base(self):
        cache=ContextCache();a=self.prepare(cache,self.context())
        b=self.prepare(cache,self.context(),reference='new catalog')
        self.assertNotEqual(a['key'],b['key']);self.assertEqual(b['diagnostic']['mode'],'base')

    def test_recent_experience_window_advances_without_forgetting_or_rebasing(self):
        cache=ContextCache();base=self.context()
        working=base['self']['working_context']
        working['recent_turns']=[{'event':{'id':str(i),'text':'自己的经历'}} for i in range(12)]
        working['event_id_aliases']={'e'+str(i):str(i) for i in range(12)}
        a=self.prepare(cache,base);current=copy.deepcopy(base)
        working=current['self']['working_context']
        working['recent_turns']=working['recent_turns'][1:]+[{'event':{'id':'12','text':'新的经历'}}]
        working['event_id_aliases']={'e'+str(i):str(i+1) for i in range(12)}
        working['earlier_today']={'conversation':{'experience_ref':'detail_1','count':1}}
        current['self']['memory_access']['available_counts']['heard']=4
        b=self.prepare(cache,current)
        self.assertEqual(b['diagnostic']['mode'],'update')
        self.assertEqual(a['messages'][0],b['messages'][0])
        self.assertEqual(restore(base,json.loads(b['messages'][-1])['context_update']),current)

    def test_restored_world_does_not_retransmit_rolled_back_experience(self):
        cache=ContextCache();future=self.context()
        future['self']['working_context']['recent_turns']=[{'event':{'id':'future','text':'存档之后才听见的原话'}}]
        self.prepare(cache,future,config=dict(self.config,context_scope='before_restore'))
        restored=self.context();restored['self']['working_context']['recent_turns']=[]
        packet=self.prepare(cache,restored,config=dict(self.config,context_scope='after_restore'))
        self.assertFalse('存档之后才听见的原话' in ''.join(packet['messages']),'恢复之后不得发送已回滚的经历')
        self.assertEqual(packet['diagnostic']['mode'],'base')

    def test_erased_memory_knowledge_and_relationship_are_not_retransmitted(self):
        for kind in ('history','counts','location','relationship'):
            cache=ContextCache();base=self.context()
            base['self']['short_term']=[{'id':'direct_memory','text':'直接提供的记忆'}]
            a=self.prepare(cache,base);current=copy.deepcopy(base)
            if kind=='history':current['self']['short_term']=[]
            elif kind=='counts':current['self']['memory_access']['available_counts']['heard']=2
            elif kind=='location':current['self']['working_context']['last_known_locations']={}
            else:current['self']['relationships']={}
            b=self.prepare(cache,current)
            self.assertEqual(b['diagnostic']['reason'],'memory_context_changed')
            self.assertEqual(len(b['messages']),1);self.assertNotEqual(a['messages'],b['messages'])

    def test_retrieved_memory_and_correction_are_only_in_current_suffix(self):
        cache=ContextCache();context=self.context()
        a=self.prepare(cache,context,suffix='\n本次检索：旧细节')
        b=self.prepare(cache,context,suffix='\n本次校验：新细节')
        self.assertNotIn('旧细节',a['messages'][0]);self.assertNotIn('旧细节',''.join(b['messages']))
        self.assertEqual(json.loads(b['messages'][-1])['context_update']['supplement'],'\n本次校验：新细节')

    def test_cache_is_bounded_and_unstructured_requests_are_unchanged(self):
        cache=ContextCache(limit=2)
        for person in ('one','two','three'):self.prepare(cache,self.context(person))
        self.assertEqual(len(cache._bases),2)
        self.assertEqual(self.prepare(cache,self.context('one'))['diagnostic']['mode'],'base')
        for prompt in ('not json','{}','{"self":null}','{"self":{"id":"one"}}'):
            self.assertIsNone(cache.prepare(prompt,'rules','catalog',self.config))

    def test_unconfirmed_baseline_is_not_used_after_incomplete_generation(self):
        cache=ContextCache();first=cache.prepare(json.dumps(self.context()),'rules','catalog',self.config)
        current=self.context();current['self']['needs']['hunger']=17
        second=cache.prepare(json.dumps(current),'rules','catalog',self.config)
        self.assertEqual(second['diagnostic']['mode'],'base')
        self.assertEqual(second['diagnostic']['reason'],'base_unconfirmed')
        cache.confirm(first['key'],first['diagnostic']['base_id'])
        self.assertFalse(cache._bases[first['key'].removeprefix('leader-context-v1-')]['ready'])

    def test_upstream_expiry_or_partial_hit_rebases_without_extra_model_call(self):
        for cached in (0,4096):
            cache=ContextCache();first=self.prepare(cache,self.context())
            cache.confirm(first['key'],first['diagnostic']['base_id'],25000)
            self.assertTrue(cache.observe_miss(first['key'],first['diagnostic']['base_id'],cached))
            fresh=self.context();fresh['self']['needs']['hunger']=17
            packet=self.prepare(cache,fresh)
            self.assertEqual(packet['diagnostic']['mode'],'base')
            self.assertEqual(packet['diagnostic']['reason'],'upstream_cache_miss')
        cache=ContextCache();packet=self.prepare(cache,self.context())
        cache.confirm(packet['key'],packet['diagnostic']['base_id'],25000)
        self.assertFalse(cache.observe_miss(packet['key'],packet['diagnostic']['base_id'],None))
        self.assertFalse(cache.observe_miss(packet['key'],packet['diagnostic']['base_id'],24576))

    def test_real_adapter_transmits_updates_and_preserves_reported_usage(self):
        sent=[];response={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'{}'}]}],
                          'usage':{'input_tokens':25000,'input_tokens_details':{'cached_tokens':24000}}}
        class Opener:
            def open(inner,request,timeout):
                sent.append(json.loads(request.data))
                return io.BytesIO(('data: '+json.dumps({'type':'response.completed','response':response})+'\n').encode())
        with patch('text_model.CACHE',ContextCache()),patch('text_model.urllib.request.build_opener',return_value=Opener()):
            first=text_model.complete(json.dumps(self.context()),self.config,prefix='rules',reference='catalog',context_scope='fixture-world')
            context=self.context();context['self']['needs']['hunger']=17
            second=text_model.complete(json.dumps(context),self.config,prefix='rules',reference='catalog',context_scope='fixture-world')
        self.assertTrue(first['ok']);self.assertTrue(second['ok']);self.assertEqual(len(sent),2)
        self.assertEqual(sent[0]['input'][:3],sent[1]['input'][:3])
        self.assertEqual(sent[0]['prompt_cache_key'],sent[1]['prompt_cache_key'])
        self.assertEqual(second['usage']['input_tokens_details']['cached_tokens'],24000)
        self.assertEqual(second['context_cache']['mode'],'update')
        self.assertNotIn('fixture-world',json.dumps(sent))

    def test_unscoped_caller_cannot_reuse_a_world_baseline(self):
        config=dict(self.config);config.pop('context_scope')
        self.assertIsNone(ContextCache().prepare(json.dumps(self.context()),'rules','catalog',config))


if __name__=='__main__':unittest.main()
