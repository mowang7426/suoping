#!/usr/bin/env python3
from pathlib import Path
s=Path('Tweak.xm').read_text()
assert 'failedResourceKey' in s and 'failedSignature' not in s
assert 'RemoveOverlayQuiet(label)' in s
assert 'SyncClock' not in s
# draw implementations must remain read-only and local; no global UIView visibility hooks.
start=s.index('static void LabelDraw')
end=s.index('static void LabelLayout',start)
draw=s[start:end]
for bad in ('Apply(', 'Schedule(', 'RemoveOverlay(', 'setNeedsDisplay'):
    assert bad not in draw, bad
assert 'setAlpha:' not in s and 'setHidden:' not in s
# Private label hooks are limited to actual class-owned methods.
hook=s.index('static void InstallClockHooks')
assert 'class_copyMethodList' in s[hook:]
assert 'setText:' in s[hook:] and 'setAttributedText:' in s[hook:]
assert 'resourceGeneration' in s and 'submissionGeneration' in s
print('wake strategy static contract passed')
