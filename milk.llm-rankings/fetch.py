#!/usr/bin/env python3
"""Official Artificial Analysis Free API -> local cache for the widget.

Keeps (a) every model that has an Intelligence Index score and (b) EVERY model from
the labs listed in labs.json, scored or not (unscored ones still have price/speed).

Usage: fetch.py [--auto|--manual]
  --auto    hourly timer / startup: skipped if the cache is under 50 minutes old
  --manual  Refresh button: skipped if the cache is under 60 seconds old

Request budget (free tier = 100/day, one full refresh = ~4 pages): automatic
refreshes stop at 90/day so the Refresh button keeps working up to 98/day.
"""
import fcntl
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

CACHE = Path.home() / '.cache/milk-llm-rankings/artificial-analysis.json'
KEY = Path.home() / '.config/omarchy/credentials/artificial-analysis.key'
LABS_FILE = Path(__file__).resolve().with_name('labs.json')
SOURCE = 'https://artificialanalysis.ai/'
ENDPOINT = SOURCE + 'api/v2/language/models/free'
SCHEMA = 4
DEFAULT_LABS = ['OpenAI', 'Anthropic', 'Google', 'Meta', 'SpaceXAI', 'Alibaba']
CAP_AUTO, CAP_MANUAL = 90, 98
FRESH_AUTO, FRESH_MANUAL = 50 * 60, 60
LEVELS = {'minimal': 'minimal', 'low': 'low', 'medium': 'medium', 'high': 'high',
          'xhigh': 'xhigh', 'x-high': 'xhigh', 'max': 'max',
          'non-reasoning': 'off', 'no reasoning': 'off', 'off': 'off'}


class FetchError(Exception):
    pass


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
            temporary = stream.name
            json.dump(data, stream, allow_nan=False)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def number(value):
    if isinstance(value, bool):
        return None
    return value if isinstance(value, (int, float)) and math.isfinite(value) and value >= 0 else None


def split_name(name):
    """'Claude Opus 5.5 (Max, Default Fallback)' -> ('Claude Opus 5.5', 'max')."""
    match = re.search(r'\s*\(([^()]*)\)\s*$', name)
    if not match:
        return name, ''
    level, rest = '', []
    for token in (t.strip() for t in match.group(1).split(',')):
        key = token.lower()
        if not token or key == 'default fallback':
            continue
        if not level and key in LEVELS:
            level = LEVELS[key]
        else:
            rest.append(token)
    label = name[:match.start()] + (' (' + ', '.join(rest) + ')' if rest else '')
    return label, level


def top_labs():
    labs = read_json(LABS_FILE, DEFAULT_LABS)
    labs = [l for l in labs if isinstance(l, str) and l.strip()] if isinstance(labs, list) else []
    return labs or DEFAULT_LABS


def read_key():
    value = os.environ.get('ARTIFICIAL_ANALYSIS_API_KEY', '').strip()
    if not value:
        try:
            value = KEY.read_text().strip()
        except FileNotFoundError:
            return ''
    if any(ord(c) < 33 or ord(c) > 126 for c in value):
        raise FetchError('Invalid API key format. Run API key setup again.')
    return value


def budget_path():
    return CACHE.with_name('request-budget.json')


def budget_count():
    day = datetime.now(timezone.utc).date().isoformat()
    budget = read_json(budget_path(), {})
    return day, (budget.get('count', 0) if budget.get('date') == day else 0)


def get_page(key, page, cap):
    day, count = budget_count()
    if count >= cap:
        raise FetchError('Daily free API budget used (%d/%d). Refresh works again after 00:00 UTC.' % (count, cap))
    atomic_json(budget_path(), {'date': day, 'count': count + 1})
    request = Request(ENDPOINT + '?page=' + str(page), headers={
        'x-api-key': key, 'Accept': 'application/json', 'User-Agent': 'milk-llm-rankings/4.0'})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def rankings(key, cap, labs, expected_pages):
    day, count = budget_count()
    if count + expected_pages > cap:
        raise FetchError('Not enough of today\'s free API budget left for a full refresh (%d/%d used).' % (count, cap))
    models, version, pages = {}, None, 0
    for page in range(1, 21):
        result = get_page(key, page, cap)
        pages += 1
        current_version = result.get('intelligence_index_version')
        if version is not None and current_version != version:
            raise FetchError('Index changed during refresh. Please retry.')
        version = current_version
        for model in result['data']:
            models[model['id']] = model
        if not result.get('pagination', {}).get('has_more', False):
            break
    else:
        raise FetchError('Unexpected API pagination; saved rankings preserved.')

    def score(m):
        return number((m.get('evaluations') or {}).get('artificial_analysis_intelligence_index'))

    def lab(m):
        return (m.get('model_creator') or {}).get('name') or 'Unknown'

    wanted = set(labs)
    keep = [m for m in models.values() if score(m) is not None or lab(m) in wanted]
    if sum(1 for m in keep if score(m) is not None) < 25:
        raise FetchError('API returned fewer than 25 scored models; saved rankings preserved.')
    keep.sort(key=lambda m: (-(score(m) if score(m) is not None else -1), m['name']))
    present = {lab(m) for m in models.values()}
    items = []
    for position, model in enumerate(keep, 1):
        performance = model.get('performance') or {}
        pricing = model.get('pricing') or {}
        label, level = split_name(model['name'])
        value = score(model)
        items.append({'position': position, 'id': model['id'], 'name': model['name'],
                      'label': label, 'level': level, 'provider': lab(model),
                      'score': round(value, 1) if value is not None else None,
                      'releaseDate': model.get('release_date') or '',
                      'speed': number(performance.get('median_output_tokens_per_second')),
                      'latency': number(performance.get('median_time_to_first_token_seconds')),
                      'inputPrice': number(pricing.get('price_1m_input_tokens')),
                      'outputPrice': number(pricing.get('price_1m_output_tokens')),
                      'url': SOURCE + 'models/' + quote(model['slug'], safe='')})
    return {'items': items, 'updated': time.time(), 'indexVersion': version, 'source': SOURCE,
            'schema': SCHEMA, 'pages': pages, 'labs': labs, 'missingLabs': [l for l in labs if l not in present],
            'totalModels': len(models), 'stale': False, 'error': '', 'needsKey': False}


def refresh(auto):
    cached = read_json(CACHE, {'items': [], 'updated': 0, 'source': SOURCE})
    labs = top_labs()
    needs_key = False
    try:
        key = read_key()
        if not key:
            return dict(cached, stale=bool(cached['items']), needsKey=True,
                        error='Add a free Artificial Analysis API key to load live rankings.')
        fresh = FRESH_AUTO if auto else FRESH_MANUAL
        if cached.get('schema') == SCHEMA and cached.get('labs') == labs and time.time() - cached.get('updated', 0) < fresh:
            return cached
        result = rankings(key, CAP_AUTO if auto else CAP_MANUAL, labs, cached.get('pages', 4))
        atomic_json(CACHE, result)
        return result
    except HTTPError as error:
        needs_key = error.code in (401, 403)
        message = {401: 'API key rejected. Run API key setup again.',
                   403: 'API access denied. Check your Artificial Analysis account.',
                   429: 'Free API rate limit reached. Try again later.'}.get(
                       error.code, 'Artificial Analysis returned HTTP ' + str(error.code) + '.')
    except URLError:
        message = 'Cannot reach Artificial Analysis. Check connection and retry.'
    except FetchError as error:
        message = str(error)
    except (OSError, ValueError, KeyError, TypeError):
        message = 'Could not refresh Artificial Analysis data. Saved rankings preserved.'
    return dict(cached, stale=True, needsKey=needs_key, error=message)


def main():
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    with CACHE.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = refresh('--auto' in sys.argv)
    print(json.dumps(result, allow_nan=False))


if __name__ == '__main__':
    main()
