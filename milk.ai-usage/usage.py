#!/usr/bin/env python3
"""Read subscription limits; never writes or prints authentication credentials."""
import concurrent.futures, datetime, fcntl, json, os, pathlib, selectors, subprocess, time, urllib.request, urllib.error
HOME = pathlib.Path.home()
CACHE = HOME / '.cache/ai-usage'
CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)

def codex():
    p = subprocess.Popen([str(HOME / '.local/share/mise/installs/codex/latest/bin/codex'), 'app-server'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        def send(obj):
            p.stdin.write(json.dumps(obj)+'\n'); p.stdin.flush()
        send({'id':1,'method':'initialize','params':{'clientInfo':{'name':'omarchy_usage','version':'1.0.0'}}})
        sel=selectors.DefaultSelector(); sel.register(p.stdout, selectors.EVENT_READ)
        deadline=time.monotonic()+25
        while time.monotonic()<deadline:
            if not sel.select(1): continue
            line=p.stdout.readline()
            if not line: raise RuntimeError('Codex exited')
            msg=json.loads(line)
            if msg.get('id')==1:
                if 'error' in msg: raise RuntimeError('Codex initialization failed')
                send({'method':'initialized'}); send({'id':2,'method':'account/rateLimits/read'})
            if msg.get('id')==2:
                if 'error' in msg: raise RuntimeError('Codex usage unavailable; check login')
                result=msg['result']; limits=result.get('rateLimitsByLimitId',{}).get('codex') or result['rateLimits']
                windows={}
                for w in (limits.get('primary'),limits.get('secondary')):
                    if w and w.get('windowDurationMins') in (300,10080):
                        windows['5h' if w['windowDurationMins']==300 else 'week']={'used':w['usedPercent'],'reset':w.get('resetsAt')}
                if not windows: raise RuntimeError('No subscription windows reported')
                return windows
        raise RuntimeError('Codex usage timed out')
    finally:
        p.terminate()
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired: p.kill(); p.wait()

def claude():
    auth=json.loads((HOME/'.claude/.credentials.json').read_text())['claudeAiOauth']
    req=urllib.request.Request('https://api.anthropic.com/api/oauth/usage', headers={'Authorization':'Bearer '+auth['accessToken'],'anthropic-beta':'oauth-2025-04-20','User-Agent':'omarchy-usage/1.0'})
    with urllib.request.urlopen(req,timeout=20) as response: data=json.load(response)
    result={}
    for key,label in [('five_hour','5h'),('seven_day','week')]:
        w=data.get(key)
        if w and isinstance(w.get('utilization'),(int,float)):
            reset=w.get('resets_at')
            result[label]={'used':w['utilization'],'reset':datetime.datetime.fromisoformat(reset.replace('Z','+00:00')).timestamp() if reset else None}
    if not result: raise RuntimeError('No subscription windows reported')
    return result

def fetch(name,func):
    path=CACHE/(name+'.json')
    try: state=json.loads(path.read_text())
    except (OSError,ValueError): state={}
    now=time.time()
    if now>=state.get('retryAt',0):
        try:
            state={'windows':func(),'updated':time.time(),'error':'','retryAt':now+120,'failures':0}
        except Exception as exc:
            failures=state.get('failures',0)+1
            if isinstance(exc,urllib.error.HTTPError):
                error={401:'Sign in again',403:'Usage access denied',429:'Rate limited'}.get(exc.code,'Service error '+str(exc.code))
            elif isinstance(exc,FileNotFoundError): error='Sign in with the CLI'
            else: error='Usage unavailable'
            state.update(error=error,failures=failures,retryAt=now+min(900,120*2**min(failures-1,3)))
        tmp=path.with_suffix('.tmp'); tmp.write_text(json.dumps(state)); tmp.replace(path)
    state['name']=name.capitalize()
    state['stale']=bool(state.get('error')) or now-state.get('updated',0)>300
    return state

def main():
    with (CACHE/'lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            jobs=[pool.submit(fetch,n,f) for n,f in [('codex',codex),('claude',claude)]]
            print(json.dumps([j.result() for j in jobs]))
if __name__=='__main__': main()
