"""按问题分类的只读证据目录；原始宿主记录不删改，不整包塞进编写工程。"""
import json

CATEGORIES = {
    'navigation': {'approach','walk_options','look_toward','recall_locations'},
    'holding': {'grasp','release','move_held','change_grip','check_placement','observe'},
    'resources': {'take_unit','put_unit','consume_unit','consume_contents','fill_container','transfer_contents','inspect_contents','access_source'},
    'handover': {'handover','give_unit'},
}

class EvidenceIndex:
    def __init__(self, export):
        self.export = export
        self.serial = 0

    def file(self, value, label):
        self.serial += 1
        path = f'reference/details/{self.serial:05d}.json'
        packed = self.pack(value, label)
        self.export(path, packed)
        return {'evidence_file': path, 'topic': label,
                'meaning': '按需读取；历史证据不是当前世界事实'}

    def pack(self, value, label='evidence'):
        if isinstance(value, dict):
            result = {}
            for key, child in value.items():
                if key == 'trace' and isinstance(child, list):
                    groups = {}
                    for index, step in enumerate(child):
                        op = step.get('operation','')
                        category = next((k for k, ops in CATEGORIES.items() if op in ops), 'observation_and_other')
                        entry = {'step': index, 'operation': op,
                                 'ok': step.get('result',{}).get('ok'),
                                 'code': step.get('result',{}).get('code'),
                                 **self.file(step, f'{category}/{op}/{index}')}
                        groups.setdefault(category, []).append(entry)
                    result[key] = {category: {'count': len(entries), **self.file(entries, category)}
                                   for category, entries in groups.items()}
                elif len(json.dumps(child, ensure_ascii=False)) > 3000:
                    result[key] = self.file(child, label+'/'+key)
                else:
                    result[key] = child
            return result
        if isinstance(value, list):
            if len(value) > 8:
                return {'count':len(value), 'pages': [
                    {'start':i, 'end':min(i+8,len(value)), **self.file(value[i:i+8], label)}
                    for i in range(0,len(value),8)]}
            return [self.pack(x,label) for x in value]
        if isinstance(value,str) and len(value)>3000:
            return {'text_length':len(value),'parts':[self.file(value[i:i+3000],label) for i in range(0,len(value),3000)]}
        return value
