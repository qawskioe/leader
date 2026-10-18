"""同一人物的短期传输基准；只压缩请求，不储存或执行模型决定。"""
from collections import OrderedDict
import hashlib
import json
import threading

ENCODING = ('现场传输：context_base是完整基准现场。context_update的set按path覆盖值，'
            'remove删除字段，得到本次完整现场；path中的字符串是对象字段，整数是从0开始的数组下标。数组长度变化以完整数组覆盖。'
            'current_event和supplement是本次内容，取代基准中的对应部分。'
            '依据重建后的self、现场与本次事件作决定。')


def changes(base, current, path=()):
    """逐字段及等长数组下标比较；长度变化仍整体替换，不移动或删除数组元素。"""
    if isinstance(base, dict) and isinstance(current, dict):
        sets, removed = [], []
        for key in base.keys() - current.keys():
            removed.append(list(path + (key,)))
        for key, value in current.items():
            if key not in base:
                sets.append({'path': list(path + (key,)), 'value': value})
            else:
                child_sets, child_removed = changes(base[key], value, path + (key,))
                sets.extend(child_sets); removed.extend(child_removed)
        return sets, removed
    if isinstance(base,list) and isinstance(current,list) and len(base)==len(current):
        sets,removed=[],[]
        for index,(old,new) in enumerate(zip(base,current)):
            child_sets,child_removed=changes(old,new,path+(index,))
            sets.extend(child_sets);removed.extend(child_removed)
        if not sets and not removed:return [],[]
        replacement=[{'path':list(path),'value':current}]
        # 滑动窗口或大幅重排可能让下标更新更大，此时仍保留较短的整块表示。
        encode=lambda value:json.dumps(value,ensure_ascii=False,separators=(',',':'))
        if len(encode({'set':sets,'remove':removed}))<len(encode({'set':replacement,'remove':[]})):
            return sets,removed
        return replacement,[]
    if type(base) is not type(current) or base != current:
        return [{'path': list(path), 'value': current}], []
    return [], []


def restore(base, update):
    result = json.loads(json.dumps(base))
    for path in update['remove']:
        parent = result
        for key in path[:-1]:
            parent = parent[key]
        del parent[path[-1]]
    for item in update['set']:
        parent = result
        for key in item['path'][:-1]:
            parent = parent[key]
        parent[item['path'][-1]] = item['value']
    result['current_event'] = update['current_event']
    return result


def _history_ids(context):
    working = context['self'].get('working_context', {})
    ids = set()
    def visit(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key in ('id', 'event_id') and isinstance(child, str):
                    ids.add(child)
                visit(child)
        elif isinstance(value, list):
            for child in value: visit(child)
    # recent_turns窗口和本轮别名会推进；旧经历仍在earlier_today目录中，
    # 不属于遗忘。它们随更新完整替换，不用临时展示编号判定记忆撤出。
    visit(context['self'].get('short_term', []))
    ids.update('known:' + key for key in working.get('last_known_locations', {}))
    ids.update('relationship:' + key for key in context['self'].get('relationships', {}))
    return ids


class ContextCache:
    def __init__(self, limit=16):
        self.limit = limit
        self._bases = OrderedDict()
        self._lock = threading.Lock()

    def confirm(self, key, base_id, input_tokens=None):
        with self._lock:
            entry = self._bases.get(key.removeprefix('leader-context-v1-'))
            if entry and entry['id'] == base_id:
                entry['ready'] = True
                entry['input_tokens'] = input_tokens

    def observe_miss(self, key, base_id, cached_tokens):
        if not isinstance(cached_tokens,int):
            return False
        with self._lock:
            entry = self._bases.get(key.removeprefix('leader-context-v1-'))
            if not entry or entry['id'] != base_id:
                return False
            expected = entry.get('input_tokens')
            if cached_tokens == 0 or (isinstance(expected,int) and cached_tokens < expected * 0.8):
                entry['ready'] = False
                entry['reset_reason'] = 'upstream_cache_miss'
                return True
            return False

    def prepare(self, prompt, prefix, reference, config):
        scope = config.get('context_scope')
        if not isinstance(scope, str) or not scope:
            return None
        # 仅处理完整人物现场；回忆路由、技能编写及非JSON请求沿用各自协议。
        try:
            current, end = json.JSONDecoder().raw_decode(prompt)
        except (ValueError, TypeError):
            return None
        if not isinstance(current, dict) or not isinstance(current.get('self'), dict):
            return None
        person = current['self'].get('id')
        if not isinstance(person, str) or not person or not isinstance(current.get('current_event'), dict):
            return None
        suffix = prompt[end:]
        identity = [config['url'], config['key'], config['model'],
                    config.get('instructions', ''), config.get('reasoning_effort', 'low'),
                    config.get('service_tier'), prefix, reference, person, scope]
        digest = hashlib.sha256(json.dumps(identity, ensure_ascii=False).encode()).hexdigest()
        cache_key = 'leader-context-v1-' + digest
        counts = current['self'].get('memory_access', {}).get('available_counts', {})
        history = _history_ids(current)
        budget = 250000 - len(prefix) - len(reference) - len(ENCODING) - 8
        with self._lock:
            entry = self._bases.get(digest)
            reset = 'first_context'
            if entry and entry['ready']:
                # 真正撤出的直接记忆、知识和关系不能继续留在传输基准中。
                revoked = not entry['history'].issubset(history) or any(
                    counts.get(kind, 0) < amount for kind, amount in entry['counts'].items())
                if revoked:
                    reset = 'memory_context_changed'
                else:
                    sets, removed = changes(entry['context'], current)
                    sets = [item for item in sets if item['path'] != ['current_event']
                            and item['path'][:1] != ['current_event']]
                    removed = [path for path in removed if path[:1] != ['current_event']]
                    update = {'base_id': entry['id'], 'set': sets, 'remove': removed,
                              'current_event': current['current_event'], 'supplement': suffix}
                    assert restore(entry['context'], update) == current, 'Context update changed world information'
                    encoded = json.dumps({'context_update': update}, ensure_ascii=False, separators=(',', ':'))
                    if len(encoded) < len(prompt) * 0.75 and len(entry['message']) + len(encoded) <= budget:
                        self._bases.move_to_end(digest)
                        return {'messages': [entry['message'], encoded], 'key': cache_key,
                                'diagnostic': {'mode': 'update', 'base_id': entry['id'],
                                               'original_chars': len(prompt), 'new_context_chars': len(encoded),
                                               'base_chars': len(entry['message'])}}
                    reset = 'update_not_smaller'
            elif entry:
                reset = entry.get('reset_reason','base_unconfirmed')
            base_id = hashlib.sha256(json.dumps(current, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:16]
            message = json.dumps({'base_id': base_id, 'context_base': current, 'supplement': ''},
                                 ensure_ascii=False, separators=(',', ':'))
            self._bases[digest] = {'id': base_id, 'context': current, 'message': message,
                                   'history': history, 'counts': counts, 'ready': False}
            self._bases.move_to_end(digest)
            while len(self._bases) > self.limit:
                self._bases.popitem(last=False)
            messages = [message]
            if suffix:
                messages.append(json.dumps({'context_update': {'base_id': base_id, 'set': [], 'remove': [],
                                                              'current_event': current['current_event'], 'supplement': suffix}},
                                           ensure_ascii=False, separators=(',', ':')))
            if sum(map(len,messages)) > budget:
                self._bases.pop(digest,None)
                return None
            return {'messages': messages, 'key': cache_key,
                    'diagnostic': {'mode': 'base', 'base_id': base_id, 'reason': reset,
                                   'original_chars': len(prompt), 'new_context_chars': len(message)}}


CACHE = ContextCache()
