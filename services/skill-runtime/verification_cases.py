"""隔离条件合同：只改变测试前提，不改变世界规则、候选源码或验收标准。"""
import math

def validate(cases,request,parameters):
    if not isinstance(cases,list) or len(cases)>4:raise ValueError('隔离场景最多4项')
    if not cases:return cases
    snapshot=request['verification_snapshot'];actor=snapshot['person_id'];known=snapshot.get('observations',{}).get(actor,{})
    names=set()
    for case in cases:
        if not isinstance(case,dict) or set(case)!={'name','steps'}:raise ValueError('隔离场景字段无效')
        name=case['name'];steps=case['steps']
        if not isinstance(name,str) or not 1<=len(name)<=80 or name in names:raise ValueError('隔离场景名称无效或重复')
        names.add(name)
        if not isinstance(steps,list) or not 1<=len(steps)<=3:raise ValueError('每个隔离场景需要1至3步')
        for index,step in enumerate(steps):
            if not isinstance(step,dict) or set(step)-{'after_operations','request','cancel_after_operation'} not in ({'conditions','arguments'},{'conditions','resume_previous'}):raise ValueError('隔离步骤字段无效')
            if 'request' in step and (not isinstance(step['request'],str) or not step['request'].isascii() or not step['request'].isidentifier() or len(step['request'])>64):raise ValueError('隔离请求标签须为64字符内的ASCII标识')
            if 'resume_previous' in step:
                if index==0 or step['resume_previous'] is not True:raise ValueError('续办只能使用同一场景上一步的resume_arguments')
                if 'cancel_after_operation' in steps[index-1]:raise ValueError('被取消步骤没有返回resume_arguments；下一步请使用完整arguments并沿用同一请求')
            elif not isinstance(step['arguments'],dict) or set(step['arguments'])!=set(parameters):raise ValueError('隔离调用参数不完整')
            if 'cancel_after_operation' in step:
                checkpoint=step['cancel_after_operation']
                if not isinstance(checkpoint,dict) or set(checkpoint)!={'operation','occurrence'}:raise ValueError('取消触发点需要operation和occurrence')
                if checkpoint['operation'] not in request.get('world_operations',[]) or type(checkpoint['occurrence']) is not int or not 1<=checkpoint['occurrence']<=4:raise ValueError('取消须绑定已开放世界操作的前4次成功结果')
            hooks=step.get('after_operations',[])
            if not isinstance(hooks,list) or len(hooks)>3:raise ValueError('隔离步骤最多3项执行期变化')
            triggers=set()
            for hook in hooks:
                if not isinstance(hook,dict) or set(hook)!={'operation','occurrence','conditions'}:raise ValueError('执行期变化字段无效')
                if hook['operation'] not in request.get('world_operations',[]) or type(hook['occurrence']) is not int or not 1<=hook['occurrence']<=4:raise ValueError('执行期变化须绑定已开放操作的前4次成功结果')
                trigger=(hook['operation'],hook['occurrence'])
                if trigger in triggers:raise ValueError('执行期变化触发点重复')
                triggers.add(trigger)
            validate_conditions(step['conditions'],snapshot,actor,known,allow_actor=True)
            for hook in hooks:validate_conditions(hook['conditions'],snapshot,actor,known)
    return cases

def validate_conditions(conditions,snapshot,actor,known,allow_actor=False):
    if not isinstance(conditions,list) or len(conditions)>4:raise ValueError('隔离前提最多4项')
    for condition in conditions:
        if not isinstance(condition,dict):raise ValueError('隔离前提不是对象')
        kind=condition.get('kind')
        if kind=='consume_to_quantity':
            if set(condition)!={'kind','object','quantity'}:raise ValueError('容器前提字段无效')
            obj=condition['object'];quantity=condition['quantity']
            if obj not in snapshot['containers'] or snapshot['objects'][obj]['holder']!=actor:raise ValueError('只能消耗本人原本实际持有的容器')
            if type(quantity) is not int or not 0<=quantity<=len(snapshot['containers'][obj]):raise ValueError('隔离消耗不得生成或补充物资')
        elif kind=='reference_distance':
            if set(condition)!={'kind','person','reference','distance_m','bearing_degrees'}:raise ValueError('参考点距离前提字段无效')
            person=condition['person'];reference=condition['reference']
            if person==actor:
                if not allow_actor:raise ValueError('受检人物仅可在调用前布置，不能在操作期间搬动')
            elif 'person/'+str(person) not in known or (person!='player' and person not in snapshot['people']):raise ValueError('只能布置受检人物或本人已知参与者')
            if not isinstance(reference,str) or reference not in known:raise ValueError('参考点必须是本人原本已知对象')
            position=known[reference].get('position')
            if not isinstance(position,list) or len(position)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) for x in position):raise ValueError('已知参考点位置无效')
            for key,low,high in [('distance_m',1,8),('bearing_degrees',-180,180)]:
                value=condition[key]
                if type(value) not in (int,float) or not math.isfinite(value) or not low<=value<=high:raise ValueError('参考点距离或方位超出范围')
        elif kind in ('participant_distance','participant_occluded','restore_participant','participant_behavior','participant_handover_answer'):
            expected={'kind','person'}|({'distance_m'} if kind=='participant_distance' or (kind=='participant_occluded' and 'distance_m' in condition) else {'behavior'} if kind=='participant_behavior' else {'answer'} if kind=='participant_handover_answer' else set())
            if set(condition)!=expected:raise ValueError('人物前提字段无效')
            person=condition['person']
            if person==actor or 'person/'+str(person) not in known or (person!='player' and person not in snapshot['people']):raise ValueError('只能设置本人已知的其他参与者')
            if kind=='participant_handover_answer' and person=='player':raise ValueError('玩家按当前世界接收规则处理，不提供模拟拒绝条件')
            if kind=='participant_distance' or (kind=='participant_occluded' and 'distance_m' in condition):
                value=condition['distance_m']
                if type(value) not in (int,float) or not math.isfinite(value) or not 1<=value<=8:raise ValueError('隔离距离须为1至8米')
            elif kind=='participant_behavior' and condition['behavior'] not in ('stay','follow_actor'):
                raise ValueError('隔离参与者仅支持停留或正常碰撞跟随')
            elif kind=='participant_handover_answer' and condition['answer'] not in ('accept','decline'):
                raise ValueError('隔离递交回复仅支持接受或拒绝')
        else:raise ValueError('未开放的隔离前提类型')
