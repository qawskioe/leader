"""从完整时间索引选择动作关键阶段；不按稀疏列表下标均匀抽样。"""

def select_frames(frames, limit=16):
    if len(frames)<=limit:return frames
    chosen={0,len(frames)-1}
    operations={}
    for index,frame in enumerate(frames):
        if ' / ' in frame['stage']:
            op=frame['stage'].split(' / ',1)[0]
            operations.setdefault(op,[]).append(index)
    # 释放瞬间及随后下落，不能被大量等候/观察帧挤掉。
    for index in operations.get('release',[])[:1]:
        chosen.add(index)
        for delta in (500,1200):
            later=next((i for i in range(index+1,len(frames)) if frames[i]['time_ms']>=frames[index]['time_ms']+delta),len(frames)-1)
            chosen.add(later)
    priority=('grasp','reach_point','release','pose_bones','pose','move_held','reach','change_grip','take_unit','put_unit','consume_unit','consume_contents','transfer_contents','give_unit','handover','fill_container','relax','approach','look_toward')
    for op in priority:
        indices=operations.get(op,[])
        for index in ([indices[0],indices[-1]] if indices else []):
            if len(chosen)<limit:chosen.add(index)
    # 剩余额度填补时间跨度最大的空隙，保留行进等前后过程。
    while len(chosen)<limit:
        remaining=set(range(len(frames)))-chosen
        if not remaining:break
        index=max(remaining,key=lambda i:(min(abs(frames[i]['time_ms']-frames[j]['time_ms']) for j in chosen),-i))
        chosen.add(index)
    return [frames[i] for i in sorted(chosen)]


def select_samples(samples, frames, limit=120):
    """保留图像对应时刻及全程分布采样；仅审查显示精度为0.1毫米。"""
    if not samples:return []
    indices={0,len(samples)-1}
    for frame in frames:
        indices.add(min(range(len(samples)),key=lambda i:abs(samples[i]['time_ms']-frame['time_ms'])))
    room=max(0,limit-len(indices))
    if len(samples)>limit:
        for i in range(room):indices.add(round(i*(len(samples)-1)/max(1,room-1)))
    else:indices=set(range(len(samples)))
    def display(value):
        if isinstance(value,float):return round(value,4)
        if isinstance(value,list):return [display(item) for item in value]
        if isinstance(value,dict):return {key:display(item) for key,item in value.items()}
        return value
    return [display(samples[i]) for i in sorted(indices)]
