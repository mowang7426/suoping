#!/usr/bin/env python3
"""Executable source contract checks. Not a substitute for UIKit/device tests."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Tweak.xm').read_text()
apply=s[s.index('static void Apply(UILabel *label) {'):s.index('static void InstallHooks(void) {')]
ready=s[s.index('static BOOL ClockReplacementReady(UILabel *label) {'):s.index('static void Apply(UILabel *label) {')]
assert 'if (!clock && !state.hidOriginalLabel)' in apply, 'clock must never hide UIView alpha'
assert 'label.hidden=YES' not in apply
assert 'UIView *dateParent=clock ? label : DateOverlayParent(label)' in apply
assert 'state.dateHost.position=CGPointMake(CGRectGetMidX(label.bounds)+offsetX' in apply
assert 'CATransform3DScale(label.layer.transform' not in apply, 'native transform must not be applied twice'
assert 'if (!image || !HasAlpha(image))' in apply
assert apply.index('ApplyStyle(label,state,state.dateHost') < apply.index('state.clockCommitted=YES')
assert 'if (!ClockReplacementReady(label))' in apply
for contract in ['ImportedFont', 's.maskHasInk', 's.dateHost.superlayer==label.layer',
                 's.gradient.superlayer==s.dateHost', 's.gradient.mask==s.mask',
                 'CGRectIntersectsRect', 'v.clipsToBounds', 'Visible(label)',
                 'DateSignature(label)', 'CGColorGetAlpha', 'LSGCCanReplaceClock(ready)']:
    assert contract in ready, contract
assert s.count('if (!Rendering && ClockReplacementReady((UILabel *)obj)) return;')==2
assert 's.clockCommitted=NO; [label setNeedsDisplay]' in s
assert 'class_copyMethodList(cls,&count)' in s
assert '@"setTransform:",@"setBounds:",@"setCenter:"' not in s
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
print('OK: commit-after-attach/style, mask/font/visibility/clip guards, glyph-only fallback, single native transform, no polling')
