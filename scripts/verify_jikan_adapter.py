#!/usr/bin/env python3
from pathlib import Path
import subprocess
root=Path(__file__).parents[1]
s=(root/'LSGCJikanETAAdapter.m').read_text()
assert 'CFPreferencesCopyValue' in s and 'moe.waru.jikan.estimate-status' in s
for token in ('CoreML','JikanPowerd','SQLite','dispatch_sync','NSTimer','CADisplayLink','system("','popen('):
    assert token not in s, token
for token in ('status','available','estimateSource','algorithm','timestamp','remainingSeconds','seconds','targetPercent'):
    assert token in s, token
assert '86400' in s and '300' in s and 'LSGCJikanETAInvalidate' in s
p=root/'/tmp-no-such'
exe=Path('/tmp/jikan_eta_adapter_policy_test')
subprocess.check_call(['clang++','-std=c++17',str(root/'tests/jikan_eta_adapter_policy_test.cpp'),'-o',str(exe)])
subprocess.check_call([str(exe)])
print('PASS Jikan adapter policy: validation, units, target, stale, source, generation, forbidden APIs')
