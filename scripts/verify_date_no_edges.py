#!/usr/bin/env python3
"""Source regression contracts; UIKit/device rendering is not asserted."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]; s=(r/'Tweak.xm').read_text()
assert 'BuildEdgeImages' not in s and 'InstallEdgeContents' not in s and 'ApplyEdges' not in s
assert 'LSGC.OptionalColorEdges' not in s
style=s[s.index('static void ApplyStyle('):s.index('static void InstallMask(')]
for k in ['edgeCore','edgeWidth','edgeHighlight','edgeEnabled']:
    assert f'Config[@"{k}"]' not in s
assert '} else ClearEdges(s);' in style
apply=s[s.index('static void Apply(UILabel *label) {'):s.index('static void InstallHooks(void) {')]
assert apply.index('ClearEdges(state); // Also purge legacy edges') < apply.index('LSGCClockAction action=clock ? LSGCClockNext(input)')
assert '[s.edgeHost removeFromSuperlayer]' in s
snapshot=s[s.index('static UIImage *SnapshotText('):s.index('// Preserve original highlights')]
assert '[text removeAttribute:NSStrokeWidthAttributeName range:all]' in snapshot
assert '[text removeAttribute:NSStrokeColorAttributeName range:all]' in snapshot
assert 'if (!IsStandaloneTimeLabel(label)) return base;' in s
assert 'if (!clock && state.hidOriginalLabel) label.alpha=0.0;' in apply
items=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())['items']
keys={i['key'] for i in items if 'key' in i}
for k in ['edgeEnabled','edgePalette','edgeCore','edgeStrength','edgeWidth','edgeHighlight','edgeReveal','independentEdges','edgeColor1','edgeColor2','edgeColor3']:
    assert k not in keys
assert all(i.get('action')!='resetEdges' for i in items)
assert '彩边' not in (r/'Preferences/Resources/Root.plist').read_text()
for k in ['clockWeight','clockEdgeEnabled','clockEdgeWidth','clockEdgeStrength','clockEdgeColor']:
    assert k in keys and f'Config[@"{k}"]' in s
assert 's.clockRim.strokeColor=s.clockRim.fillColor' in style
assert 'insertSublayer:s.clockRim below:s.gradient' in style
assert all(f'color{i}' in keys for i in range(1,6))
print('OK: date/lunar solid gradient only, no edge generation/mount/config, legacy cleanup on cache hits, native replacement and isolated geometry retained; main-clock outline/shared five colors retained')
