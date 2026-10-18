import copy,unittest
from verification_cases import validate
class CaseTests(unittest.TestCase):
    def test_known_reference_placements_are_only_host_conditions_and_actor_is_not_moved_mid_operation(self):
        self.request['verification_snapshot']['observations']['a']['water_source']={'position':[1,0,2]}
        condition={'kind':'reference_distance','person':'a','reference':'water_source','distance_m':1.5,'bearing_degrees':90}
        step={'conditions':[condition],'arguments':{}}
        cases=[{'name':'one_sided','steps':[step]}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        for changed in [dict(condition,person='hidden'),dict(condition,reference='unknown'),dict(condition,distance_m=True),dict(condition,distance_m=float('nan')),dict(condition,bearing_degrees=181),dict(condition,position=[0,0,0])]:
            step['conditions']=[changed]
            with self.assertRaises(ValueError):validate(cases,self.request,{})
        step['conditions']=[];step['after_operations']=[{'operation':'consume_contents','occurrence':1,'conditions':[condition]}]
        with self.assertRaisesRegex(ValueError,'调用前'):validate(cases,self.request,{})
        condition['person']='player'
        self.assertEqual(validate(cases,self.request,{}),cases)

    def test_cancel_checkpoint_is_bound_to_an_open_successful_operation(self):
        checkpoint={'operation':'consume_contents','occurrence':1}
        step={'conditions':[],'arguments':{},'cancel_after_operation':checkpoint}
        cases=[{'name':'cancel_then_resume','steps':[step,{'conditions':[],'arguments':{}}]}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        for invalid in [None,[],{},dict(checkpoint,operation='run_code'),dict(checkpoint,occurrence=True),
                        dict(checkpoint,occurrence=0),dict(checkpoint,occurrence=5),dict(checkpoint,quantity=2)]:
            step['cancel_after_operation']=invalid
            with self.assertRaises(ValueError):validate(cases,self.request,{})

    def test_cancelled_step_cannot_supply_unreturned_resume_arguments(self):
        steps=[{'conditions':[],'arguments':{},'cancel_after_operation':{'operation':'consume_contents','occurrence':1}},
               {'conditions':[],'resume_previous':True}]
        with self.assertRaisesRegex(ValueError,'arguments'):
            validate([{'name':'cancelled_parameters','steps':steps}],self.request,{})

    def test_handover_answers_are_known_recipient_test_conditions(self):
        condition={'kind':'participant_handover_answer','person':'b','answer':'decline'}
        steps=[{'conditions':[condition],'arguments':{}},{'conditions':[dict(condition,answer='accept')],'resume_previous':True}]
        cases=[{'name':'declined_then_accepted','steps':steps}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        for changed in [dict(condition,person='a'),dict(condition,person='hidden'),dict(condition,person='player'),dict(condition,answer='force_transfer'),dict(condition,quantity=2)]:
            steps[0]['conditions']=[changed]
            with self.assertRaises(ValueError):validate(cases,self.request,{})

    def test_occlusion_is_a_bounded_known_participant_test_condition(self):
        condition={'kind':'participant_occluded','person':'player','distance_m':6}
        cases=[{'name':'hidden_then_return','steps':[{'conditions':[condition],'arguments':{}}]}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        cases[0]['steps'][0]['conditions']=[{'kind':'participant_occluded','person':'player'}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        for change in [dict(condition,person='hidden'),dict(condition,distance_m=100),dict(condition,visible_now=False)]:
            cases[0]['steps'][0]['conditions']=[change]
            with self.assertRaises(ValueError):validate(cases,self.request,{})

    def test_participant_can_stop_following_then_resume_without_new_candidate_permissions(self):
        steps=[{'conditions':[{'kind':'participant_behavior','person':'player','behavior':'stay'}],'arguments':{}},
               {'conditions':[{'kind':'participant_behavior','person':'player','behavior':'follow_actor'}],'resume_previous':True}]
        cases=[{'name':'cooperation_changes','steps':steps}]
        self.assertEqual(validate(cases,self.request,{}),cases)
        for change in [{'kind':'participant_behavior','person':'hidden','behavior':'stay'},
                       {'kind':'participant_behavior','person':'player','behavior':'teleport'},
                       {'kind':'participant_behavior','person':'player','behavior':'follow_actor','gravity':0}]:
            steps[0]['conditions']=[change]
            with self.assertRaises(ValueError):validate(cases,self.request,{})

    def setUp(self):
        self.request={'world_operations':['consume_contents','handover'],'verification_snapshot':{'person_id':'a','people':{'a':{},'b':{}},'objects':{'bag':{'holder':'a'}},'containers':{'bag':[{},{}]},'observations':{'a':{'person/player':{},'person/b':{}}}}}
        self.steps=[{'conditions':[{'kind':'participant_distance','person':'player','distance_m':6}], 'arguments':{'object':'bag','return_only':False}},
                    {'conditions':[{'kind':'restore_participant','person':'player'}], 'resume_previous':True}]
    def test_empty_and_continuous_cases(self):
        cases=[{'name':'empty','steps':[{'conditions':[{'kind':'consume_to_quantity','object':'bag','quantity':0}], 'arguments':{'object':'bag','return_only':False}}]}, {'name':'blocked_resume','steps':self.steps}]
        self.assertEqual(validate(cases,self.request,{'object':'reference','return_only':'boolean'}),cases)
        self.assertEqual(validate([],{},{}),[])
    def test_cannot_create_contents_or_modify_unknown_participant(self):
        for condition in [{'kind':'consume_to_quantity','object':'bag','quantity':3}, {'kind':'participant_distance','person':'hidden','distance_m':6}, {'kind':'participant_distance','person':'a','distance_m':6}, {'kind':'participant_distance','person':'player','distance_m':float('nan')}, {'kind':'change_world_rule','gravity':0}]:
            cases=[{'name':'bad','steps':[{'conditions':[condition],'arguments':{}}]}]
            with self.assertRaises(ValueError):validate(cases,self.request,{})
        self.request['verification_snapshot']['objects']['bag']['holder']='b'
        with self.assertRaises(ValueError):validate([{'name':'other','steps':[{'conditions':[{'kind':'consume_to_quantity','object':'bag','quantity':0}],'arguments':{}}]}],self.request,{})
    def test_resume_requires_previous_result_and_arguments_contract(self):
        for steps in [[self.steps[1]], [{'conditions':[],'arguments':{}}], [{'conditions':[],'arguments':{'object':'bag','return_only':False},'code':'arbitrary'}]]:
            with self.assertRaises(ValueError):validate([{'name':'bad','steps':steps}],self.request,{'object':'reference','return_only':'boolean'})
    def test_metadata_bounds(self):
        for value in [{},[{'name':'x','steps':[]}], [{'name':'x','steps':[{'conditions':[],'arguments':{}}]}]*5]:
            with self.assertRaises(ValueError):validate(value,self.request,{})
    def test_after_successful_operation_uses_same_condition_boundary(self):
        step=copy.deepcopy(self.steps[0]);step['conditions']=[]
        hook={'operation':'consume_contents','occurrence':1,'conditions':[{'kind':'participant_distance','person':'player','distance_m':6}]}
        step['after_operations']=[hook]
        cases=[{'name':'moves_after_drinking','steps':[step,self.steps[1]]}]
        self.assertEqual(validate(cases,self.request,{'object':'reference','return_only':'boolean'}),cases)
        for invalid in [dict(hook,operation='run_code'),dict(hook,occurrence=True),dict(hook,occurrence=0),dict(hook,conditions=[{'kind':'change_world_rule'}])]:
            step['after_operations']=[invalid]
            with self.assertRaises(ValueError):validate(cases,self.request,{'object':'reference','return_only':'boolean'})
        step['after_operations']=[hook,hook]
        with self.assertRaises(ValueError):validate(cases,self.request,{'object':'reference','return_only':'boolean'})
    def test_new_request_labels_do_not_add_world_permissions(self):
        steps=copy.deepcopy(self.steps)
        steps[1]['request']='another_order'
        cases=[{'name':'request_scope','steps':steps}]
        self.assertEqual(validate(cases,self.request,{'object':'reference','return_only':'boolean'}),cases)
        for value in [1,'','other/request','其他请求','x'*65]:
            steps[1]['request']=value
            with self.assertRaises(ValueError):validate(cases,self.request,{'object':'reference','return_only':'boolean'})
if __name__=='__main__':unittest.main()
