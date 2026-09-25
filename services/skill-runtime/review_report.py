"""生成本地可读审查页；不调用模型，不改变技能状态。"""
import html
import json
from pathlib import Path

def write_report(folder):
    folder=Path(folder)
    status=json.loads((folder/'status.json').read_text(encoding='utf-8'))
    review=status.get('review',{})
    if not review:
        files=sorted(folder.glob('visual_review_*.json'))
        if files:review=json.loads(files[-1].read_text(encoding='utf-8'))
    esc=lambda value:html.escape(str(value),quote=True)
    request_file=folder/'build_request.json'
    revision=json.loads(request_file.read_text(encoding='utf-8')).get('revision',{}) if request_file.exists() else {}
    summary=('修订未通过，新版本未加载；旧版本保留' if revision else '首次学习未通过，尚未掌握此技能') if status.get('state')=='failed' else status.get('message','审查记录')
    parts=['<!doctype html><meta charset="utf-8"><title>人物动作审查</title><style>body{background:#171b20;color:#eee;font:18px/1.6 sans-serif;max-width:1100px;margin:32px auto;padding:0 24px}section{background:#242a31;padding:20px;margin:16px 0;border-radius:12px}figure{display:inline-block;width:46%;vertical-align:top;margin:1%}img{width:100%}pre{white-space:pre-wrap;font-size:14px}a{color:#8ecaff}small{color:#bac2cb}</style>',
           '<h1>人物动作审查</h1><p>任务：'+esc(folder.name)+'</p>',
           '<section><b>'+esc(summary)+'</b><p>以下区分宿主数值检查和模型意见；模型的故障归因不等于已确认的程序根因。</p>']
    for issue in review.get('issues',[]):
        if isinstance(issue,dict) and 'problem' in issue:
            parts.append('<p><b>'+esc(round(issue.get('time_ms',0)/1000,2))+' 秒：</b>'+esc(issue.get('problem',''))+'</p><p>建议：'+esc(issue.get('suggestion',''))+'</p>')
        elif isinstance(issue,dict):
            returned=issue.get('runtime',{}).get('returned',{})
            summary='；'.join(str(x) for x in issue.get('failures',[])) or '回放返回了执行问题'
            if isinstance(returned,dict):summary+=' · '+str(returned.get('code',''))
            parts.append('<p>'+esc(summary)+'</p><details><summary>展开程序执行证据</summary><pre>'+esc(json.dumps(issue,ensure_ascii=False,indent=2))+'</pre></details>')
        else:parts.append('<p>'+esc(issue)+'</p>')
    plan_file=folder/'outcome_plan.json'
    if plan_file.exists():
        parts.append('<details><summary>编写前确定的验收条件与说明</summary><pre>'+esc(plan_file.read_text(encoding='utf-8'))+'</pre></details>')
    for outcome_file in sorted(folder.glob('motion_*/outcomes.json')):
        outcomes=json.loads(outcome_file.read_text(encoding='utf-8'))
        parts.append('<h3>'+esc(outcome_file.parent.name)+' · 宿主结果检查</h3>')
        for check in outcomes['checks']:
            parts.append('<p>'+('通过' if check['passed'] else '未通过')+'：'+esc(check['description'])+'；测量值 '+esc(check['measured'])+'</p>')
        if not outcomes['checks']:parts.append('<p>没有可数值判定的条件；仍需独立模型验收。</p>')
    parts.append('</section><h2>回放关键帧</h2><p>点击图片打开原图。灰地面和蓝色圆片是验证场景的接触参考。</p>')
    for motion in sorted(folder.glob('motion_*/motion.json')):
        data=json.loads(motion.read_text(encoding='utf-8'))
        parts.append('<h3>'+esc(motion.parent.name)+'</h3>')
        selected=motion.parent/'review_frames.json'
        frames=json.loads(selected.read_text(encoding='utf-8')) if selected.exists() else data.get('frames',[])
        parts.append('<p>'+('实际提交给审查模型的关键帧' if selected.exists() else '回放预览；本轮尚无审查选帧记录')+'</p>')
        for frame in frames:
            href=esc(motion.parent.name+'/'+frame['file'])
            parts.append('<figure><a href="'+href+'"><img loading="lazy" src="'+href+'"></a><figcaption>'+esc(round(frame['time_ms']/1000,2))+' 秒 · '+esc(frame['stage'])+'</figcaption></figure>')
    source=folder/'source.luau'
    if source.exists():parts.append('<section><details><summary>本次技能源码</summary><pre>'+esc(source.read_text(encoding='utf-8'))+'</pre></details></section>')
    parts.append('<p><a href="status.json">完整状态 JSON</a></p>')
    target=folder/'review.html';target.write_text('\n'.join(parts),encoding='utf-8');return target

if __name__=='__main__':
    import sys
    print(write_report(Path(sys.argv[1])))
