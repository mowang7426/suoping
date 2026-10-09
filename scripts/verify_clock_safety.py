#!/usr/bin/env python3
"""Executable source contract checks. Not a substitute for UIKit/device tests."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Tweak.xm').read_text()
apply=s[s.index('static void Apply(UILabel *label) {'):s.index('static void InstallHooks(void) {')]
ready=s[s.index('static BOOL ClockReplacementReady(UILabel *label) {'):s.index('static void Apply(UILabel *label) {')]
assert 'if (!clock && !state.hidOriginalLabel)' in apply, 'clock must never hide UIView alpha'
assert 'label.hidden=YES' not in apply
assert 'UIView *dateParent=clock ? ClockOverlayParent(label,&hostReason) : DateOverlayParent(label)' in apply
assert 'CGPoint center=[label convertPoint:CGPointMake(CGRectGetMidX(label.bounds)+offsetX' in apply
assert 'CATransform3DScale(label.layer.transform' not in apply, 'native transform must not be applied twice'
assert 'if (!image || !HasAlpha(image))' in apply
assert apply.index('ApplyStyle(label,state,state.dateHost') < apply.index('state.clockCommitted=YES')
assert 'LSGCClockCommit(action,ClockReplacementReady(label))' in apply
for contract in ['ImportedFont', 's.maskHasInk', 's.dateHost.superlayer==s.clockHost.layer',
                 's.gradient.superlayer==s.dateHost', 's.gradient.mask==s.mask',
                 'CGRectIntersectsRect', 's.clockHost.bounds', 'ClockHostVisible(label,s)',
                 'DateSignature(label)', 'CGColorGetAlpha', 'LSGCCanReplaceClock(ready)']:
    assert contract in ready, contract
assert s.count('if (!Rendering && ClockReplacementReady((UILabel *)obj)) { if (main) DiagInc(&DiagSuppress); return; }')==2
assert 's.clockCommitted=NO; [label setNeedsDisplay]' in s
assert 'class_copyMethodList(cls,&count)' in s
assert '@"setTransform:",@"setBounds:",@"setCenter:"' not in s
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
print('OK: commit-after-attach/style, mask/font/visibility/clip guards, glyph-only fallback, single native transform, no polling')

helper=s[s.index('static UIView *ClockSelectOverlayParent'):s.index('static UIView *DateOverlayParent')]
assert 'LSGCAllowSourceWrapper(true,' in helper
assert 'v.hidden || v.layer.hidden' in helper
assert 'bypass && v==wrapper' in helper
assert 's.dateHost.opacity*s.gradient.opacity>=0.01' in helper
assert 'LSGCClockCommonOpacityValid' in helper
assert 'unsupported-source-3d-transform' in helper
assert 'host!=s.clockHost' in helper
assert 'source-invalid-geometry' in helper
assert 'if (!tracked && !glass && !IsStandaloneTimeLabel(label)' in s
assert 'if (IsStandaloneTimeLabel(label)) return nil;' in s
assert 'if (clock && !dateParent)' in apply
assert apply.index('BOOL clock=IsStandaloneTimeLabel(label)') < apply.index('DateOverlayParent(label)')
assert 'label.clipsToBounds=NO' not in apply
print('OK: main-clock independent of date-only, restricted alpha-zero source wrapper host, ordinary low-alpha ancestors rejected')
