#!/usr/bin/env python3
from pathlib import Path
s=Path('Tweak.xm').read_text()
h=Path('LSGCWakeStrategy.h').read_text()
t=Path('tests/wake_strategy_test.cpp').read_text()
assert '#import "LSGCWakeStrategy.h"' in s
for token in ('failedEarly','currentResource','currentSubmission','wakePolicy.commit','wakePolicy.failTransient','wakePolicy.removeQuiet','LSGCShouldQueueWake','LSGCSetterGuard','LSGCResourceBindingConsistent','cachedResourceGeneration'):
    assert token in s, token
assert 'LSGCWakePolicy' in t and '#include "../LSGCWakeStrategy.h"' in t
assert 'failedEarly' in t and 'currentSubmission' in t and 'removeQuiet' in t
assert 'resourceGeneration' in h and 'submissionGeneration' in h
start=s.index('static void LabelDraw'); end=s.index('static void LabelLayout',start); draw=s[start:end]
for bad in ('Apply(', 'Schedule(', 'RemoveOverlay(', 'setNeedsDisplay'): assert bad not in draw, bad
assert 'setAlpha:' not in s and 'setHidden:' not in s
print('wake strategy production contract passed')
