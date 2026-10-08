#!/usr/bin/env python3
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]; s=(r/'Tweak.xm').read_text()
a=s[s.index('static void ApplyStyle('):s.index('static void InstallMask(')]
settings={x['key']:x for x in plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())['items'] if 'key' in x}
for k in ['clockMode','clockColor','clockColor1','clockColor2','clockColor3','clockColor4']:
    assert k not in settings and f'Config[@"{k}"]' not in s
for i in range(1,6): assert f'color{i}' in settings
for marker in ['i<5','@"color%lu"','ShiftedColor(c,hue)','reverseColors','customStopsEnabled','gradientAngle','animate','s.revision!=Revision']:
    assert marker in a, marker
assert 's.dateHost && !standaloneTime) s.gradient.opacity=1' in a
snapshot=s[s.index('static UIImage *SnapshotText('):s.index('// Preserve original highlights')]
assert 'if (!clock) {' in snapshot and 'removeAttribute:NSStrokeWidthAttributeName' in snapshot
apply=s[s.index('static void Apply(UILabel *label) {'):s.index('static void InstallHooks(void) {')]
assert apply.index('state.signature=signature;') < apply.index('if (!clock && state.hidOriginalLabel) label.alpha=0.0;')
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
print('OK: shared five-color/hue/direction/animation pipeline, explicit revision invalidation, date solid mask/full fill/cache-hit native suppression')
