"""官方 Chat Completions SSE；只接受正常停止的完整 JSON 文字。"""
import json
import time
import urllib.error
import urllib.request


def complete(prompt, config):
    started = time.monotonic()
    payload = {
        'model': config['model'],
        'messages': [
            {'role': 'system', 'content': config.get('instructions', '你是游戏角色决策接口。只输出一个合法 JSON 对象。')},
            {'role': 'user', 'content': prompt},
        ],
        'thinking': {'type': config.get('thinking', 'disabled')},
        'response_format': {'type': 'json_object'},
        'max_tokens': config.get('max_tokens', 1500),
        'stream': True,
        'stream_options': {'include_usage': True},
    }
    request = urllib.request.Request(config['url'], data=json.dumps(payload).encode('utf-8'), headers={
        'Authorization': 'Bearer ' + config['key'], 'Content-Type': 'application/json',
        'User-Agent': 'Leader-Prototype/0.1', 'Accept': 'text/event-stream',
    })
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=config.get('read_timeout_seconds',45)) as response:
            return read_stream(response, started, config['model'])
    except urllib.error.HTTPError as exc:
        return {'ok': False, 'error': 'DeepSeek HTTP ' + str(exc.code), 'retryable': exc.code in (408,429,500,502,503,504)}
    except OSError:
        return {'ok':False,'error':'DeepSeek 网络或读取超时','retryable':True}
    except (ValueError, TypeError):
        return {'ok': False, 'error': 'DeepSeek 网络或流格式错误'}


def read_stream(response, started, model):
    text = ''
    usage = {}
    first = None
    finish = None
    done = False
    for raw in response:
        if time.monotonic() - started > 60:
            return {'ok': False, 'error': 'DeepSeek 流超时', 'retryable':True}
        if not raw.startswith(b'data:'):
            continue
        data = raw[5:].strip()
        if data == b'[DONE]':
            done = True
            break
        event = json.loads(data)
        if event.get('error'):
            return {'ok': False, 'error': 'DeepSeek 返回错误事件'}
        model = event.get('model', model)
        if event.get('usage'):
            usage = event['usage']
        for choice in event.get('choices', []):
            piece = choice.get('delta', {}).get('content') or ''
            if piece and first is None:
                first = round((time.monotonic() - started) * 1000)
            text += piece
            if len(text) > 100000:
                return {'ok': False, 'error': 'DeepSeek 输出超出限制'}
            if choice.get('finish_reason'):
                finish = choice['finish_reason']
    if not done or finish != 'stop' or not text.strip():
        return {'ok': False, 'error': 'DeepSeek 返回不完整，未执行人物决定'}
    return {'ok': True, 'text': text, 'model': model, 'usage': usage, 'completion': finish,
            'first_text_ms': first, 'elapsed_ms': round((time.monotonic() - started) * 1000)}
