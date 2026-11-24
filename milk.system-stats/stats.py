"""Read local counters without elevated privileges or background daemons."""
import glob
import json
from pathlib import Path


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


result = {}
cpu = read('/proc/stat')
if cpu:
    ticks = list(map(int, cpu.splitlines()[0].split()[1:9]))
    result['total'] = sum(ticks)
    result['idle'] = ticks[3] + ticks[4]
memory = read('/proc/meminfo')
if memory:
    mem = {line.split(':')[0]: int(line.split()[1]) for line in memory.splitlines()}
    result['memoryTotal'] = mem['MemTotal']
    result['memoryUsed'] = mem['MemTotal'] - mem['MemAvailable']
info = read('/proc/cpuinfo') or ''
result['cpuName'] = next((line.split(':', 1)[1].strip() for line in info.splitlines() if line.startswith('model name')), 'CPU')
result['load'] = (read('/proc/loadavg') or '').split()[:3]
for card in sorted(glob.glob('/sys/class/drm/card[0-9]*')):
    if read(card + '/device/vendor') != '0x8086':
        continue
    result['gpuName'] = 'Intel integrated graphics'
    for key, filename in [('gpuMHz', 'gt_act_freq_mhz'), ('gpuMin', 'gt_min_freq_mhz'), ('gpuMax', 'gt_max_freq_mhz')]:
        value = read(card + '/' + filename)
        if value is not None:
            result[key] = int(value)
    break
print(json.dumps(result))
